# bad_ldap_server
Bad insecure non-compliant ruby ldap server for testing ldap clients

You probably want to avoid this :)

This does not currently work under jruby due to: https://github.com/inscitiv/ruby-ldapserver/issues/3

I included a .ruby-version file to make using rvm easier (for me). It currently assumes you have `ruby-1.9.3-p551` installed. You should either install that or use a different native ruby and update the file as appropriate.

To use...

- Clone to location of your choice.
- run `bundle install`
- run using `ruby bad_ldap_server.rb`
- it will run on port 1389 and load 'example.ldif' by default. 
- run `ruby bad_ldap_server.rb -h` to see help on options

