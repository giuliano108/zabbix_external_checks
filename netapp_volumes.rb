#!/home/deploy/.rvm/rubies/ruby-1.9.3-p194/bin/ruby
#
# Requires:
#   - The "snmp" gem
#   - the imported "netapp.mib" MIB module (NETAPP-MIB.yaml)
#   If you want to import the netapp module yourself (generate the YAML equivalent):
#     - libsmi (brew install libsmi).
#     - the actual import goes like this: SNMP::MIB.import_module('mibs/netapp.mib', '.')
# Returned values are in KB

require 'snmp'
require 'timeout'

MaxTime             = 20
ZabbixSender        = File.join(File.dirname(__FILE__), 'zabbix_sender')
ZabbixSenderCmdLine = "#{ZabbixSender} -z 10.1.2.3 -s 'Zabbix Server' -i -"
ZabbixKeys = {
    'head1:/vol/vol1/' => 'san.netapp.vol1',
    'head1:/vol/vol2/' => 'san.netapp.vol2',
    'head2:/vol/vol3/' => 'san.netapp.vol3',
    'head2:/vol/vol4/' => 'san.netapp.vol4'
}

data = {}
Timeout::timeout(MaxTime) do
    ['head1','head2'].each do |head|
        SNMP::Manager.open(:host => head,
                           :mib_dir => File.dirname(__FILE__),
                           :mib_modules => ['NETAPP-MIB']) do |manager|
            dfNumber = manager.get_value('dfNumber.0');
            response = manager.get_bulk(0, dfNumber.to_i, ['dfFileSys','df64AvailKBytes'])
            list = response.varbind_list
            until list.empty?
                dfFileSys       = list.shift
                df64AvailKBytes = list.shift
                data[head + ':'+ dfFileSys.value.to_s] = df64AvailKBytes.value.to_i
            end
        end
    end
end

zabbix_data = ''
data.each do |k,v|
    if ZabbixKeys.has_key? k
        zabbix_data << "- #{ZabbixKeys[k]} #{v}\n"
    end
end

exit if zabbix_data.empty?

Timeout::timeout(MaxTime) do
    IO.popen(ZabbixSenderCmdLine, :mode => 'w+', :external_encoding => Encoding::ASCII_8BIT) do |file|
        file.write zabbix_data
    end 
end
