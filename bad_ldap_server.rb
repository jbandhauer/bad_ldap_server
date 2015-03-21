#!/usr/local/bin/ruby -w

# This is based on: https://github.com/inscitiv/ruby-ldapserver/blob/master/examples/rbslapd1.rb
#
# I added simple_bind, an ldif parser, comand line options, etc.

# XXX hack to disable 'assigned but unused variable' warnings from the gem we use
$VERBOSE = nil
#$debug = true

######################################################################################################

require 'json'
require 'ldap/server'
require 'ldap/server/util'

# experiment

def normalize_dn(dn)
  LDAP::Server::Operation.join_dn(LDAP::Server::Operation.split_dn(dn))
  # dn.split(',').map(&:strip).join(',').downcase
end

# We subclass the Operation class, overriding the methods to do what we need
# XXX This is currently painfully case sensitive and sensitive to exact whitespace matching in distiniguished names.

class HashOperation < LDAP::Server::Operation
  def initialize(connection, messageID, hash)
    super(connection, messageID)
    @hash = hash   # an object reference to our directory data
  end

  def search(basedn, scope, deref, filter)
    # basedn = normalize_dn(basedn)
    # basedn.downcase!

    # puts "Searching with base #{basedn}"

    case scope
    when LDAP::Server::BaseObject
      # client asked for single object by DN
      obj = @hash[basedn]
      raise LDAP::ResultError::NoSuchObject unless obj
      send_SearchResultEntry(basedn, obj) if LDAP::Server::Filter.run(filter, obj)

    when LDAP::Server::WholeSubtree
      @hash.each do |dn, av|
        # puts "  looking at #{dn}"
        next unless dn.index(basedn, -basedn.length)    # under basedn?
        # puts "    base matches"
        next unless LDAP::Server::Filter.run(filter, av)  # attribute filter?
        send_SearchResultEntry(dn, av)
      end

    else
      raise LDAP::ResultError::UnwillingToPerform, "OneLevel not implemented"

    end
  end

  def add(dn, av)
    # dn = normalize_dn(dn)
    # dn.downcase!
    raise LDAP::ResultError::EntryAlreadyExists if @hash[dn]
    @hash[dn] = av
  end

  def del(dn)
    # dn = normalize_dn(dn)
    # dn.downcase!
    raise LDAP::ResultError::NoSuchObject unless @hash.has_key?(dn)
    @hash.delete(dn)
  end

  def modify(dn, ops)
    # dn = normalize_dn(dn)
    # dn.downcase!
    entry = @hash[dn]
    raise LDAP::ResultError::NoSuchObject unless entry
    ops.each do |attr, vals|
      op = vals.shift
      case op
      when :add
        entry[attr] ||= []
        entry[attr] += vals
        entry[attr].uniq!
      when :delete
        if vals == []
          entry.delete(attr)
        else
          vals.each { |v| entry[attr].delete(v) }
        end
      when :replace
        entry[attr] = vals
      end
      entry.delete(attr) if entry[attr] == []
    end
  end

  def simple_bind(version, dn, password)
    return if dn.nil?   # accept anonymous
    # dn = normalize_dn(dn)
    # dn.downcase!

    obj = @hash[dn]
    raise LDAP::ResultError::InvalidCredentials unless obj && obj['userpassword'] == [password]
  end

end

######################################################################################################

def raise_error(str, line, line_num)
  puts "Error: #{str} ('#{line}' @ line #{line_num})"
  raise "error"
end

# XXX Bad little ldif parser. Doesn't handle line continuations, etc.
def parse_ldif(string)
  hash = {}
  dn = nil

  string.lines.each_with_index do |raw_line, line_num|
    line = raw_line.chomp!
    next if line.start_with? '#'
    next if line.strip.empty?
    next if line.start_with?('version:') && hash.empty?
    raise_error("Line continuations are not supported by this bad parser", line, line_num) if line.start_with? ' '

    line.strip!

    next if line.match(/^dn:[\s]*(.*)/) do |m|
      dn = m[1]
      hash[dn] = {}
    end

    raise_error("expected a 'dn:'", line, line_num) unless dn

    next if line.match(/^([\w]*)[\s]*:[\s](.*)/) do |m|
      hash[dn][m[1]] ||= []
      hash[dn][m[1]] << m[2]
    end

    raise_error("expected an attribute", line, line_num)
  end

  hash
end

######################################################################################################

require 'trollop'

opts = Trollop::options do
  opt :port,    "Port to run on",     :short => "-p",  :type => :int,     :default => 1389
  opt :ldif,    "LDIF file to load",  :short => "-f",  :type => :string,  :default => 'example.ldif'
end

# This is the shared object which carries our actual directory entries.
# It's just a hash of {dn=>entry}, where each entry is {attr=>[val,val,...]}

directory = {}

if opts[:ldif] && !opts[:ldif].empty?
  puts "Loading content from '#{opts[:ldif]}'"
  directory = parse_ldif(File.read(opts[:ldif]))
# puts directory.to_json
end

# Listen for incoming LDAP connections. For each one, create a Connection
# object, which will invoke a HashOperation object for each request.

server_opts = {
  :port       => opts[:port],
  :nodelay    => true,
  :listen     => 10,
# :ssl_key_file   => "key.pem",
# :ssl_cert_file    => "cert.pem",
# :ssl_on_connect   => true,
  :operation_class  => HashOperation,
  :operation_args   => [directory]
}

server = LDAP::Server.new(server_opts)
server.run_tcpserver
puts "ldap server listening on port #{server_opts[:port]}"
server.join


