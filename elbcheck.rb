#!/home/deploy/.rvm/rubies/ruby-1.9.3-p194/bin/ruby
require 'rubygems'
require 'parallel'
require 'timeout'
require 'dnsruby'
require 'json'
 
MaxThreads          = 5
MaxTime             = 10
#LastRunFile         = File.join(File.dirname(__FILE__), 'elbcheck_last_run.json')
LastRunFile         = '/var/lib/elbcheck/elbcheck_last_run.json'
ZabbixSender        = File.join(File.dirname(__FILE__), 'zabbix_sender')
ZabbixSenderCmdLine = "#{ZabbixSender} -z 10.1.2.3 -s 'Zabbix Server' -i -"
UseSyslog           = true; require 'syslog' if UseSyslog
ELBs = [
    {:key => 'uswitch.elb.apps', :hostname => 'apps-1234567.eu-west-1.elb.amazonaws.com'}
]

def log(message)
    if UseSyslog
        unless Syslog.opened?
            Syslog.open('elbcheck',Syslog::LOG_PID,Syslog::LOG_DAEMON)
        end
        Syslog.log(Syslog::LOG_NOTICE, message)
    else
        puts message
    end
end

semaphore      = Mutex.new
dns_results    = {}
zabbix_results = []

do_resolve = lambda do |elb|
    begin
        Timeout::timeout(MaxTime) do
            resolver = Dnsruby::Resolver.new :nameserver => '8.8.8.8'
            response = resolver.query(elb[:hostname], Dnsruby::Types.A)
            if !response.nil? 
                semaphore.synchronize do
                    dns_results[elb[:key]] = response.answer.map {|a| a.address.to_s}.sort
                end
            end
        end
    rescue
        semaphore.synchronize { dns_results[elb[:key]] = [] }
    end
end

Parallel.each(ELBs, :in_threads => MaxThreads, &do_resolve)

begin
    last_dns_results = JSON.parse(IO.read(LastRunFile))
rescue
    last_dns_results = {}
end

begin
    File.open(LastRunFile, 'w') { |f| f << dns_results.to_json }
rescue
end

dns_results.each do |key,rrs|
    next if !last_dns_results[key] or last_dns_results[key].empty?
    next if !dns_results[key] or dns_results[key].empty?
    if last_dns_results[key] != dns_results[key]
        log "WARNING: ELB DNS change detected - #{key} - #{ELBs.find {|e| e[:key] == key }[:hostname]} - before: #{last_dns_results[key]} - after: #{dns_results[key]}"
        zabbix_results.push({:key => key, :v => 0})
    else
        zabbix_results.push({:key => key, :v => 1})
    end
end

zabbix_data = ''
zabbix_results.each do |r|
   zabbix_data << "- #{r[:key]} #{r[:v]}\n"
end

exit if zabbix_data.empty?

Timeout::timeout(MaxTime) do
    IO.popen(ZabbixSenderCmdLine, :mode => 'w+', :external_encoding => Encoding::ASCII_8BIT) do |file|
        file.write zabbix_data
    end 
end
