# Cookbook:: rb-llm
# Provider:: config

include Rbllm::Helper

action :add do
  begin
    user = new_resource.user
    group = new_resource.group

    llm_selected_model = new_resource.llm_selected_model
    exec_start = '/usr/lib/redborder/bin/rb_llm.sh --fast --port 50505 --host 0.0.0.0'

    # Old models must have this arg
    if llm_selected_model == '5' || llm_selected_model == '7' || llm_selected_model == '8' || llm_selected_model == '9'
      exec_start += ' --nobrowser'
    end

    cpus = new_resource.cpus

    dnf_package 'redborder-llm' do
      action :upgrade
      flush_cache [:before]
    end

    execute 'create_user' do
      command "/usr/sbin/useradd -r #{user} -s /sbin/nologin"
      ignore_failure true
      not_if "getent passwd #{user}"
    end

    %w(/etc/redborder-llm /var/lib/redborder-llm var/lib/redborder-llm/model_sources).each do |path|
      directory path do
        owner user
        group user
        mode '0755'
        action :create
      end
    end

    directory "/var/lib/redborder-llm/model_sources/#{llm_selected_model}" do
      owner user
      group group
      mode '0755'
      action :create
      only_if { llm_selected_model }
    end

    directory '/etc/systemd/system/redborder-llm.service.d' do
      owner user
      group group
      mode '0755'
      action :create
    end

    ruby_block 'check_if_need_to_download_model' do
      block do
        dir_path = "/var/lib/redborder-llm/model_sources/#{llm_selected_model}"
        if Dir.exist?(dir_path) && Dir.empty?(dir_path)
          Chef::Log.info("#{dir_path} is empty, triggering run_get_llm_model")
          resources(execute: 'run_get_llm_model').run_action(:run)
        end
      end
      action :nothing
      only_if { llm_selected_model }
      notifies :restart, 'service[redborder-llm]', :delayed
    end

    execute 'run_get_llm_model' do
      command "/usr/lib/redborder/bin/rb_get_llm_model #{llm_selected_model}"
      action :nothing
    end

    service 'redborder-llm' do
      service_name 'redborder-llm'
      ignore_failure true
      supports status: true, restart: true, enable: true
      action [:start, :enable]
    end

    # Notify the ruby_block to check if the directory is empty after creating it
    ruby_block 'trigger_check_if_need_to_download_model' do
      block {}
      action :run
      notifies :run, 'ruby_block[check_if_need_to_download_model]', :immediately
      only_if { llm_selected_model }
    end

    # TEMPLATES
    template '/etc/systemd/system/redborder-llm.service.d/redborder_cpu.conf' do
      source 'redborder-llm_redborder_cpu.conf.erb'
      owner user
      group group
      mode '0644'
      retries 2
      cookbook 'rb-llm'
      variables(cpus: cpus, exec_start: exec_start)
      notifies :run, 'execute[systemctl-daemon-reload]', :delayed
      notifies :restart, 'service[redborder-llm]', :delayed
    end

    execute 'systemctl-daemon-reload' do
      command 'systemctl daemon-reload'
      action :nothing
    end

    Chef::Log.info('Redborder llm cookbook has been processed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    service 'redborder-llm' do
      service_name 'redborder-llm'
      ignore_failure true
      supports status: true, enable: true
      action [:stop, :disable]
    end

    %w(/etc/redborder-llm).each do |path|
      directory path do
        recursive true
        action :delete
      end
    end

    dnf_package 'redborder-llm' do
      action :remove
    end

    Chef::Log.info('Redborder llm cookbook has been removed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :register do
  begin
    ipaddress = new_resource.ipaddress

    unless node['redborder-llm']['registered']
      query = {}
      query['ID'] = "redborder-llm-#{node['hostname']}"
      query['Name'] = 'redborder-llm'
      query['Address'] = ipaddress
      query['Port'] = 50505
      json_query = Chef::JSONCompat.to_json(query)

      execute 'Register service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/register -d '#{json_query}' &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['redborder-llm']['registered'] = true
      Chef::Log.info('redborder-llm service has been registered to consul')
    end
  rescue StandardError => e
    Chef::Log.error(e.message)
  end
end

action :deregister do
  begin
    if node['redborder-llm']['registered']
      execute 'Deregister service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/deregister/redborder-llm-#{node['hostname']} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['redborder-llm']['registered'] = false
      Chef::Log.info('redborder-llm service has been deregistered from consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end
