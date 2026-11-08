%global repo_base @@BASE_URL@@

Name:           alejandro-md-release
Version:        1.0.0
Release:        1%{?dist}
Summary:        Package repository configuration for packages.alejandro.md

License:        MIT
URL:            @@BASE_URL@@
BuildArch:      noarch

Source0:        RPM-GPG-KEY-alejandro-md
Source1:        alejandro-md.repo

# Nothing to compile, and the key and repo file are generated at publish
# time from the live signing key.
%global debug_package %{nil}

%description
Installs the OpenPGP public key used to sign every package published at
packages.alejandro.md, and the dnf/yum repository definition that uses it.

Packages from that repository depend on this one, so the repository and key
are configured once rather than duplicated per project.

%prep
%autosetup -c -T

%build

%install
install -Dpm 0644 %{SOURCE0} \
  %{buildroot}%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-alejandro-md
install -Dpm 0644 %{SOURCE1} \
  %{buildroot}%{_sysconfdir}/yum.repos.d/alejandro-md.repo

%post
# rpm verifies package signatures against its own keyring, not the files in
# /etc/pki/rpm-gpg, so the key has to be imported explicitly.
/usr/bin/rpm --import %{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-alejandro-md || :

# Retire the per-project repo files from before the move to
# packages.alejandro.md so dnf does not carry dead baseurls.
for legacy in lcd4linux-ax206 mediasmartserverd mediasmartserver \
              unifi-gateway infrafi infrafid mariner3d mariner; do
  old="%{_sysconfdir}/yum.repos.d/${legacy}.repo"
  if [ -f "$old" ] && grep -qE 'amd989\.github\.io' "$old" 2>/dev/null; then
    mv "$old" "${old}.replaced-by-alejandro-md-release" || :
  fi
done

%files
%config(noreplace) %{_sysconfdir}/yum.repos.d/alejandro-md.repo
%{_sysconfdir}/pki/rpm-gpg/RPM-GPG-KEY-alejandro-md

%changelog
* Fri Nov 07 2026 Alejandro Mora <mail@alejandro.md> - 1.0.0-1
- Initial release, replacing the per-project repository definitions
