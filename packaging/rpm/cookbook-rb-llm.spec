%global cookbook_path /var/chef/cookbooks/rb-llm

Name: cookbook-rb-llm
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch
Summary: Redborder cookbook to install and configure redborder-rb-llm

License: AGPL 3.0
URL: https://github.com/redBorder/cookbook-rb-llm
Source0: %{name}-%{version}.tar.gz

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}%{cookbook_path}
cp -f -r  resources/* %{buildroot}%{cookbook_path}
chmod -R 0755 %{buildroot}%{cookbook_path}
install -D -m 0644 README.md %{buildroot}%{cookbook_path}/README.md

%pre
if [ -d /var/chef/cookbooks/rb-llm ]; then
    rm -rf /var/chef/cookbooks/rb-llm
fi

%post
case "$1" in
  1)
    # This is an initial install.
    :
  ;;
  2)
    # This is an upgrade.
    su - -s /bin/bash -c 'source /etc/profile && rvm gemset use default && env knife cookbook upload rb-llm'
  ;;
esac

%postun
# Deletes directory when uninstall the package
if [ "$1" = 0 ] && [ -d /var/chef/cookbooks/rb-llm ]; then
  rm -rf /var/chef/cookbooks/rb-llm
fi

%files
%defattr(0755,root,root)
%{cookbook_path}
%defattr(0644,root,root)
%{cookbook_path}/README.md

%doc

%changelog
* Thu Oct 10 2024 Miguel Negrón <manegron@redborder.com>
- Add pre and postun

* Wed Jul 24 2024 Pablo Pérez <pperez@redborder.com>
- first spec version