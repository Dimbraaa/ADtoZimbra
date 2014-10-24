ADtoZimbra
==========

AD to ZIMBRA Account Provisioning and Synchronization

This program :

- Is unidirectionnal from AD to Zimbra (no changes to Active Directory)
- Scans users by mail attributes in Active Directory (OU-based recursive search, exclusion list is optionnal)
- Scans existing zimbra users in ZCS (domain-based search, COS is optionnal)
- Can create accounts, alias, searchfolders, signature, and populate Zimbra LDAP attributes
- Can synchronize LDAP attributes values from AD to Zimbra for existing accounts

Tested with :
- Red Hat Enterprise Linux Server release 6.4 
- ZCS Release 8.0.5 NETWORK edition
- GNU bash, version 4.1.2

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
