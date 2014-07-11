#!/usr/bin/env ruby

require 'rubygems' if RUBY_VERSION < "1.9"
require 'erb'
require 'json'
require File.join(File.dirname(__FILE__), 'config-dns')

module DNSSlaved
    class DNSSlave
        
        $st_loaded = 0
        $st_curl_failed = 1
        $st_json_failed = 2
        
        def list_zones
            list = []
                
            Dir.entries($n_path + "/").each { |entry|
                list.push entry if entry[0, $n_pref.length] == $n_pref
            }
            
            list
        end
        
        def collect_from_admins
            admins = {}
            
            $dnsa.each { |adm|
                admin = {
                    "status" => $st_loaded,
                    "data" => adm,
                    "zones" => [] 
                }
                
                raw_response = `#{$command % [adm["user"], adm["password"], $slave_address, adm["address"], $route]}` ; success = $?.success?
                
                if success  
                    begin             
                        response = JSON.parse raw_response
                        
                        zones = []
                        
                        response["data"].each { |zone|
                            record = {
                                "zone" => zone,
                                "master_ip" => adm["master_ip"]
                            }            
                            
                            zones.push record
                        } 
                        
                        admin["zones"] = zones
                    rescue
                        admin["status"] = $st_json_failed
                    end
                else
                    admin["status"] = $st_curl_failed
                end  
                
                admins[adm["uname"]] = admin       
            }
            
            admins
        end
        
        def remove_zones(zones, admin) 
            out = []
            pref = $n_pref + admin + "."
                
            zones.each { |zone|
                out.push zone if !zone[0, pref.length] == pref
            }
            
            out     
        end
        
        def sync(n_tpl = "named.default.erb")
            admins = collect_from_admins
            zones = list_zones
                
            admins.each_value { |adm|
                if adm["status"] == $st_loaded
                    adm["zones"].each { |zone|
                        filename = $n_pref + adm["data"]["uname"] + "." + zone["zone"]
                            
                        zones.delete filename
                        
                        File.open($n_path + "/" + filename, "w") { |file|
                            template = ERB.new File.new($tpl_path + "/" + n_tpl).read, nil, "%"            
                            file.puts template.result(binding)
                        }
                    }
                else
                    zones = remove_zones(zones, adm["data"]["uname"])
                end
            }      
            
            zones.each { |zone|
                File.unlink($n_path + "/" + zone)
                zonefile = $z_path + "/" + $z_pref + zone[$n_pref.length, zone.length]
                File.unlink zonefile if File.exists? zonefile
            }      
            
            generate_master_named
        end
                
        def generate_master_named           
            File.open($n_path + '/' + $n_master, "w") { |file|            
                list_zones.each { |zone_name|               
                    file.write "include \"#{$n_path}/#{zone_name}\";\n"
                }
            }            
        end
                
        def reload
            puts "reloading..."
            system $r_command
        end
        
        def run!
            sync
            reload
        end
            
    end
end

DNSSlaved::DNSSlave.new.run!
