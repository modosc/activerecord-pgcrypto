require "active_record/pgcrypto/version"
require 'active_support/concern'
require 'active_record'



# load up our log_subscriber to filter out sensitive stuff
require "active_record/pgcrypto/log_subscriber"

# load up our generator if we're in rails
require "active_record/pgcrypto/railtie" if defined?(Rails)
#require "active_record/pgcrypto/generator"

module ActiveRecord
  module Pgcrypto
    require 'digest'

    extend ActiveSupport::Concern

    class << self
      attr_writer :configuration
    end

    def self.configuration
      @configuration ||= ActiveSupport::OrderedOptions.new.tap do |c|
        c.public_key = ENV['PGCRYPTO_PUBLIC_KEY']
        c.private_key = ENV['PGCRYPTO_PRIVATE_KEY']
        c.private_key_password = ENV['PGCRYPTO_PRIVATE_KEY_PASSWORD']
        c.salt = ENV['PGCRYPTO_SALT']
      end
    end

    def self.configure
      yield(configuration)
    end

    # right now this is all we are setting for pgp_pub_encrypt
    # TODO - expose this in the configuration
    ENCRYPT_OPTS = { :"compress-algo" => 2,
                     :"compress-level" => 9,
                     :"cipher-algo" => 'aes256'}

    def reset_select_manager
      @select_manager = nil
    end

    def select_manager
      @select_manager ||= Arel::SelectManager.new(self.class)
    end

    def bind_param(value)
      select_manager.bind_values << value
      Arel::Nodes::BindParam.new
    end

    def bind_params
      select_manager.bind_values.map{|v| [nil, v] }
    end

    def encode_to_hex(value)
      Arel::Nodes::NamedFunction.new 'encode', [ value, Arel::Nodes::Quoted.new('hex')]
    end

    def decode_from_hex(value)
      Arel::Nodes::NamedFunction.new 'decode', [ value, Arel::Nodes::Quoted.new('hex')]
    end

    def dearmor(key)
      Arel::Nodes::NamedFunction.new 'dearmor',
                                     [ bind_param(key) ]
    end

    def pgp_pub_decrypt(value)
      opts = [ decode_from_hex(bind_param(value)),
               dearmor(private_key) ]

      (opts << bind_param(private_key_password)) if private_key_password.present?
      Arel::Nodes::NamedFunction.new 'pgp_pub_decrypt', opts
    end

    # not currently used, see comments below near the class method
    # def pgp_pub_decrypt_column(column)
    #   encode_to_hex Arel::Nodes::NamedFunction.new 'pgp_pub_decrypt',
    #                                                [ self.class.arel_table[column],
    #                                                dearmor(private_key) ]
    # end

    def pgp_pub_encrypt(value)
      encode_to_hex Arel::Nodes::NamedFunction.new 'pgp_pub_encrypt',
                                                   [ bind_param(value),
                                                   dearmor(public_key),
                                                   Arel::Nodes::Quoted.new(ENCRYPT_OPTS.map{|k,v| "#{k}=#{v}" }.join(',')) ]
    end

    # TODO - make this configurable?
    BF_ITERATION_COUNT = 6

    def crypt(value)
      opts = [bind_param(value)]
      if salt
        opts << bind_param(salt)
      else
        opts << Arel::Nodes::NamedFunction.new('gen_salt', [Arel::Nodes::Quoted.new('bf'), BF_ITERATION_COUNT])
      end
      Arel::Nodes::NamedFunction.new 'crypt', opts
    end

    def public_key
      ActiveRecord::Pgcrypto.configuration.public_key
    end

    def private_key
      ActiveRecord::Pgcrypto.configuration.private_key
    end

    def private_key_password
      ActiveRecord::Pgcrypto.configuration.private_key_password
    end

    def salt
      ActiveRecord::Pgcrypto.configuration.salt
    end

    def pgp_decrypt(value)
      reset_select_manager
      select_manager.project pgp_pub_decrypt(value).as('decrypt')
      self.class.connection.exec_query(select_manager.to_sql, 'decrypt', bind_params).first['decrypt']
    end

    def pgp_encrypt(value)
      reset_select_manager
      select_manager.project pgp_pub_encrypt(value).as('encrypt')
      self.class.connection.exec_query(select_manager.to_sql, 'encrypt', bind_params).first['encrypt']
    end

    def digest(value)
      reset_select_manager
      select_manager.project crypt(value).as('crypt')
      self.class.connection.exec_query(select_manager.to_sql, 'crypt', bind_params).first['crypt']
    end

    included do

      # TODO - this _should_ work but it doesn't because of (what i think is) some
      # encoding issue. i can write this sql by hand in the console and it runs fine
      # so rails is trying to "help" me somehow.
      #
      # without this we potentially run into issues - consider loading up 100 users
      # and displaying them with their ssn's on a single screen (similar to a dataclip)
      # . we'll end up making 101 queries, 1 to load all 100 users and 100 to decrypt
      # each individual user's ssn. if the below default_scope worked we'd get that
      # back down to 1 query.
      # default_scope { select(Arel.star, pgp_pub_decrypt_column(:encrypted_ssn))
      #                .tap{ |arel|
      #                      arel.bind_values=[[ User.columns_hash['encrypted_ssn'],
      #                                           private_key
      #                                        ]]} }

      #private :private_key, :public_key
    end

    module ClassMethods
      # not currently used, but need from above. probably should be refactored
      # or renamed
      # def pgp_pub_decrypt_column(column)
      #   Arel::Nodes::NamedFunction.new 'pgp_pub_decrypt',
      #   [ arel_table[column],
      #   dearmor(private_key) ]
      # end

      # def dearmor(key)
      #   Arel::Nodes::NamedFunction.new 'dearmor',
      #   [  Arel::Nodes::BindParam.new ]
      # end

      def encrypted_attributes
        # store internally as a set but return as an array
        @encrypted_attributes.to_a
      end

      # TODO - make searchability optional, sometimes we just want to store
      # encrypted values that we'd never actual search on
      def has_encrypted_attributes(*args)
        attrs = args.flatten
        @encrypted_attributes ||= Set.new
        # always append so that multiple :has_encrypted_attributes clauses work correctly
        @encrypted_attributes += attrs.map(&:to_s)

        attrs.each do |a|
          # if we're encrypting this we probably don't want our controllers
          # logging our values
          if defined?(::Rails)
            Rails.application.configure do
              config.filter_parameters << a
            end
          end

          # this is the ivar we store our decrypted value in
          ivar = "@#{a}"
          encrypted_attr = "encrypted_#{a}"
          hashed_attr = "hashed_#{a}"
          # accessor - if ivar isn't defined then fetch it from the database. this
          # is potentially expensive, see default_scope comments above.
          #
          # TODO - rewrite this using http://edgeapi.rubyonrails.org/classes/ActiveRecord/Attributes/ClassMethods.html#method-i-attribute
          define_method a do
            # i can't find a more concise way to metaprogram @foo ||= bar, oh well
            unless instance_variable_defined? ivar
              # calls to super from inside the block of define_method have to have
              # the parens at the end or else ruby complains
              val = pgp_decrypt(self.send encrypted_attr.to_sym)
              begin
                val = Marshal.load ActiveRecord::Base.connection.unescape_bytea val
              rescue TypeError => e
                # not marshal'd, no big deal. noop and we use the original val we
                # loaded
              end
              instance_variable_set ivar, val
            end
            instance_variable_get ivar
          end

          define_method "#{a}=" do |value|
            instance_variable_set ivar, value

            # if value is not a string/number marshal it so we can save it
            # (numeric values get casted to strings)
            unless value.is_a?(String) || value.nil?
              value = ActiveRecord::Base.connection.escape_bytea Marshal.dump value
            end

            # if we've already got this value currently set return and don't update
            # encrypted_attr / hashed_attr. this way #changed? won't get set;
            # otherwise we'll end up with encrypted_attr changing and hashed_attr
            # remaining the same
            if value == pgp_decrypt(self.send encrypted_attr.to_sym)
              return value
            end

            digest_value = digest(value)

            # call our activerecord setter with our encrypted value
            self.send "#{encrypted_attr}=".to_sym, pgp_encrypt(value)
            # then set our hashed value as well
            self.send "#{hashed_attr}=".to_sym, digest_value
          end

          define_method "#{a}?" do
            self.send(a).present?
          end

          # now setup a scope for this class so we can search. for instance,
          # adding an encrypted :foo attribute to the Bar class means this will
          # work:
          #
          #   Bar.where(something: something_else).find_by_foo("1235")
          #
          # or this to find NULL values
          #
          #   Bar.where(something: something_else).find_by_foo(nil)
          #
          # TODO - would be nice to also add "#{a}_not" methods to invert the
          # search. not sure if we need that or not? could see querying on "IS NOT NULL",
          # not sure we'd search on "ssn != '123123'"
          #
          # also i know find_by_ is supposed to only return a single value, but i
          # figured it'd be easier to remember than search_by_* or whatever. open
          # to changing this if necessary.
          #
          # TODO: rewrite this using ActiveRecord::QueryMethods / ActiveRecord::PredicateBuilder
          scope "find_by_#{a}".to_sym, ->(val) {
            if val.nil?
              # if nil was explicitly passed in we search for a NULL value
              where self.arel_table["hashed_#{a}".to_sym].eq(nil)
            else
              unless val.is_a?(String)
                val = ActiveRecord::Base.connection.escape_bytea Marshal.dump val
              end

              # TODO - probably could refactor this with the instance methods above
              # or maybe make a new object for this instead of storing select_manager
              # and bind_params in instance variables.
              #
              # the .tap is necessary below to add bind params into our arel generated
              # query. ugly!
              crypt_opts = [Arel::Nodes::BindParam.new]
              bind_values = [[nil, val]]
              if ActiveRecord::Pgcrypto.configuration.salt
                crypt_opts << Arel::Nodes::BindParam.new
                bind_values << [nil, ActiveRecord::Pgcrypto.configuration.salt ]
              else
                crypt_opts << self.arel_table["hashed_#{a}".to_sym]
              end

              where(self.arel_table["hashed_#{a}".to_sym]
                      .eq(Arel::Nodes::NamedFunction.new('crypt', crypt_opts))
                   ).tap{ |arel| arel.bind_values += bind_values }

            end
          }
        end
      end
    end
  end
end

#
