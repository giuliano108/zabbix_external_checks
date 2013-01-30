#!/home/deploy/.rvm/rubies/ruby-1.9.3-p194/bin/ruby
require 'rubygems'
require 'parallel'
require 'timeout'
require 'net/http'
 
MaxThreads = 10
MaxTime    = 30

checks = [
    {:key => 'fetch.bmc.slave117', :uri => 'http://192.168.1.2/page/login.html',  :match => 'STR_LOGIN_PASSWORD'},
    {:key => 'fetch.bmc.slave226', :uri => 'http://192.168.1.3/xmldata?item=All', :match => 'ProLiant'}
]

semaphore = Mutex.new
results = []

checker = lambda do |check|
    begin
        Timeout::timeout(MaxTime) do
            response = Net::HTTP.get_response(URI(check[:uri]))
            response.body =~ /(#{check[:match]})/s
            semaphore.synchronize { results.push({:key => check[:key], :v => ($1.nil? ? 0 : 1)}) }
        end
    rescue
        semaphore.synchronize { results.push({:key => check[:key], :v => 0}) }
    end
end
 
ZabbixSender        = File.join(File.dirname(__FILE__), 'zabbix_sender')
ZabbixSenderCmdLine = "#{ZabbixSender} -z 10.1.2.3 -s 'Zabbix Server' -i -"

Parallel.each(checks, :in_threads => MaxThreads, &checker)

data = ''
results.each do |i|
   data << "- #{i[:key]} #{i[:v]}\n"
end

Timeout::timeout(MaxTime) do
    IO.popen(ZabbixSenderCmdLine, :mode => 'w+', :external_encoding => Encoding::ASCII_8BIT) do |file|
        file.write data
    end 
end
