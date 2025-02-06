# Cookbook:: rb-ai
# Provider:: config

include Rbai::Helper

action :add do
  begin
    user = new_resource.user
    group = new_resource.group

    ai_selected_model = new_resource.ai_selected_model
    model_name = `ls /var/lib/redborder-ai/model_sources/#{ai_selected_model}`.strip

    cpus = new_resource.cpus

    dnf_package 'redborder-ai' do
      action :upgrade
      flush_cache [:before]
    end

    execute 'create_user' do
      command "/usr/sbin/useradd -r #{user} -s /sbin/nologin"
      ignore_failure true
      not_if "getent passwd #{user}"
    end

    %w(/etc/redborder-ai /var/lib/redborder-ai /var/lib/redborder-ai/model_sources).each do |path|
      directory path do
        owner user
        group user
        mode '0755'
        action :create
      end
    end

    directory "/var/lib/redborder-ai/model_sources/#{ai_selected_model}" do
      owner user
      group group
      mode '0755'
      action :create
      only_if { !ai_selected_model.nil? && !ai_selected_model.empty? }
    end

    directory '/etc/systemd/system/redborder-ai.service.d' do
      owner user
      group group
      mode '0755'
      action :create
    end

    ruby_block 'check_if_need_to_download_model' do
      block do
        dir_path = "/var/lib/redborder-ai/model_sources/#{ai_selected_model}"
        symlink_path = '/usr/lib/redborder/bin/ai-model'
        target_path = "/var/lib/redborder-ai/model_sources/#{ai_selected_model}/#{model_name}"
        service_needs_restart = false

        if Dir.exist?(dir_path) && Dir.empty?(dir_path)
          Chef::Log.info("#{dir_path} is empty, triggering run_get_ai_model")
          resources(execute: 'run_get_ai_model').run_action(:run)
          service_needs_restart = true
        elsif Dir.exist?(dir_path) && !Dir.empty?(dir_path)
          if ::File.symlink?(symlink_path) && ::File.readlink(symlink_path) == target_path
            Chef::Log.info('Symlink already points to the correct model, skipping update.')
          else
            Chef::Log.info("#{dir_path} is not empty, triggering update_ai_model")
            resources(execute: 'update_ai_model').run_action(:run)
            service_needs_restart = true
          end
        end
        resources(service: 'redborder-ai').run_action(:restart) if service_needs_restart
      end
      action :nothing
      only_if { !ai_selected_model.nil? && !ai_selected_model.empty? }
    end

    execute 'run_get_ai_model' do
      command "/usr/lib/redborder/bin/rb_get_ai_model #{ai_selected_model}"
      action :nothing
    end

    execute 'update_ai_model' do
      command "rm -f /usr/lib/redborder/bin/ai-model; ln -s /var/lib/redborder-ai/model_sources/#{ai_selected_model}/#{model_name} /usr/lib/redborder/bin/ai-model"
      action :nothing
    end

    service 'redborder-ai' do
      service_name 'redborder-ai'
      ignore_failure true
      supports status: true, restart: true, enable: true
      action [:start, :enable]
    end

    # Notify the ruby_block to check if the directory is empty after creating it
    ruby_block 'trigger_check_if_need_to_download_model' do
      block {}
      action :run
      notifies :run, 'ruby_block[check_if_need_to_download_model]', :immediately
      only_if { !ai_selected_model.nil? && !ai_selected_model.empty? }
    end

    # TEMPLATES
    template '/etc/systemd/system/redborder-ai.service.d/redborder_cpu.conf' do
      source 'redborder-ai_redborder_cpu.conf.erb'
      owner user
      group group
      mode '0644'
      retries 2
      cookbook 'rb-ai'
      variables(cpus: cpus)
      notifies :run, 'execute[systemctl-daemon-reload]', :delayed
      notifies :restart, 'service[redborder-ai]', :delayed
    end

    execute 'systemctl-daemon-reload' do
      command 'systemctl daemon-reload'
      action :nothing
    end

    Chef::Log.info('Redborder ai cookbook has been processed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    service 'redborder-ai' do
      service_name 'redborder-ai'
      ignore_failure true
      supports status: true, enable: true
      action [:stop, :disable]
    end

    %w(/etc/redborder-ai).each do |path|
      directory path do
        recursive true
        action :delete
      end
    end

    dnf_package 'redborder-ai' do
      action :remove
    end

    Chef::Log.info('Redborder ai cookbook has been removed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :register do
  begin
    ipaddress = new_resource.ipaddress

    unless node['redborder-ai']['registered']
      query = {
        'ID' => "redborder-ai-#{node['hostname']}",
        'Name' => 'redborder-ai',
        'Address' => ipaddress,
        'Port' => 50505,
      }
      json_query = Chef::JSONCompat.to_json(query)

      execute 'Register service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/register -d '#{json_query}' &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['redborder-ai']['registered'] = true
      Chef::Log.info('redborder-ai service has been registered to consul')
    end
  rescue StandardError => e
    Chef::Log.error(e.message)
  end
end

action :deregister do
  begin
    if node['redborder-ai']['registered']
      execute 'Deregister service in consul' do
        command "curl -X PUT http://localhost:8500/v1/agent/service/deregister/redborder-ai-#{node['hostname']} &>/dev/null"
        action :nothing
      end.run_action(:run)

      node.normal['redborder-ai']['registered'] = false
      Chef::Log.info('redborder-ai service has been deregistered from consul')
    end
  rescue => e
    Chef::Log.error(e.message)
  end
end
