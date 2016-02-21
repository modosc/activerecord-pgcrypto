# stolen from https://raw.githubusercontent.com/jmazzi/crypt_keeper/master/lib/crypt_keeper/log_subscriber/postgres_pgp.rb
require 'active_support'
require 'active_support/concern'
require 'active_support/lazy_load_hooks'
require 'active_support/log_subscriber'
require 'active_support/notifications'
require 'active_support/core_ext'
require 'active_record/log_subscriber'
require 'active_support/dependencies/autoload'

module ActiveRecord::Pgcrypto
  module LogSubscriber
    extend ActiveSupport::Concern

    included do
      alias_method_chain :sql, :postgres_pgp
    end

    FILTERED_TEXT ||= '[FILTERED]'.freeze

    # Public: Prevents sensitive data from being logged
    #
    # TODO - filter out hashed_*/encrypted_* for insert / update / delete as well?
    def sql_with_postgres_pgp(event)

      event.payload[:sql] = event.payload[:sql]
        .encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
        .gsub(/((?<operation>crypt|pgp_pub_encrypt|pgp_pub_decrypt)(?<re>\((?:(?> [^()]+ )|\g<re>)*\)))/xim) do |d|
          # above regex adapted from http://stackoverflow.com/questions/6331065/matching-balanced-parenthesis-in-ruby-using-recursive-regular-expressions-like-p
          operation = $~[:operation]
          if (binds = d.scan(/(\$\d)/im)).present?
            # called with bind params - we need to filter out the appropriate values.
            # we filter out the first two bind params for pgp_public_encrypt,
            # pgp_public_decrypt, and crypt . technically we could include $1 for
            # pgp_public_decrypt (our cyphertext) and $2 for pgp_public_encrypt
            # (our pgp public key) but those are big hunks of hex data that'll
            # make reading logs harder so we strip them as well.
            #length = operation == 'crypt' ? 1 : 2
            binds[0,3].flatten.each do |bp|
              event.payload[:binds][(bp.sub('$', '').to_i - 1)][1] = FILTERED_TEXT
            end
            d
          else
            # called directly, filter out everything. we could try to extract args
            # and replace them individually but it's hard to do correctly.
            "#{operation}(#{FILTERED_TEXT})"
          end
        end

      sql_without_postgres_pgp(event)
    end

  end
end

ActiveRecord::LogSubscriber.send :include, ActiveRecord::Pgcrypto::LogSubscriber
