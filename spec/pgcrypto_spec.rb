require 'spec_helper'
#require 'rails_helper'


RSpec.describe ActiveRecord::Pgcrypto do
  CONFIG = { encoding: 'unicode',
             adapter: 'postgresql',
             database: 'activerecord_pgcrypto_test' }

  before(:all) do
    silence_stream(STDOUT) do
      ActiveRecord::Base.establish_connection(CONFIG.merge({database: 'postgres'}))
      ActiveRecord::Base.connection.create_database(CONFIG[:database])
      ActiveRecord::Base.establish_connection(CONFIG)

      ActiveRecord::Schema.define(version: 1) do
        enable_extension 'pgcrypto'
        create_table :messages do |t|
          t.boolean :flag
          t.string :encrypted_message
          t.string :hashed_message
        end
      end
    end
  end

  after(:all) do
    silence_stream(STDOUT) do
      ActiveRecord::Base.establish_connection(CONFIG.merge({database: 'postgres'}))
      ActiveRecord::Base.connection.drop_database(CONFIG[:database])
    end
  end

  # def read_key(name)
  #   File.read(File.join(RSpec::Core::RubyProject.root, 'spec/fixtures', name))
  # end

  # select gen_salt('bf')
  SALT = '$2a$06$W08w.BZCskDBfssD6kuHge'
  PASSWORD = "c7ac44eb52eb54b12a9a90ee727e0c4b"
  PUBLIC_KEY_NO_PASS = File.read(File.join(RSpec::Core::RubyProject.root, 'spec/fixtures', 'activerecord-pgcrypto-nopass@example.com.pub.gpg'))
  PUBLIC_KEY_PASS = File.read(File.join(RSpec::Core::RubyProject.root, 'spec/fixtures', 'activerecord-pgcrypto-pass@example.com.pub.gpg'))
  PRIVATE_KEY_NO_PASS = File.read(File.join(RSpec::Core::RubyProject.root, 'spec/fixtures',  'activerecord-pgcrypto-nopass@example.com.priv.gpg'))
  PRIVATE_KEY_PASS = File.read(File.join(RSpec::Core::RubyProject.root, 'spec/fixtures', 'activerecord-pgcrypto-pass@example.com.priv.gpg'))


  class Message < ActiveRecord::Base
    include ActiveRecord::Pgcrypto
    has_encrypted_attributes :message
  end

  describe '#encrypted_attributes' do
    before(:all) do
      class AnotherMessage < ActiveRecord::Base
        self.table_name = 'messages'
        include ActiveRecord::Pgcrypto
        has_encrypted_attributes :message
      end
    end

    it 'reading works' do
      expect(AnotherMessage.encrypted_attributes).to eq(['message'])
    end

    it 'writing works' do
      AnotherMessage.instance_eval do
        has_encrypted_attributes :something_else
      end

      expect(AnotherMessage.encrypted_attributes).to eq(['message', 'something_else'])

      AnotherMessage.instance_eval do
        has_encrypted_attributes :foo, :bar
      end

      expect(AnotherMessage.encrypted_attributes).to eq(['message', 'something_else', 'foo', 'bar'])
    end
  end

  shared_examples 'attribute encryption' do
    let(:message) { Message.create! }
    let(:string) { Faker::Lorem.sentence }
    let(:string2) { Faker::Lorem.sentence }
    let(:integer) { rand(1000) }
    let(:integer2) { rand(1000) + 1000 }
    let(:float) { Math::PI }
    let(:float2) { Math::E }
    let(:hash) {{ string: string, integer: integer, float: float }}
    let(:hash2) {{ string: string2, integer: integer2, float: float2 }}

    describe 'getter/setter' do
      it 'works with a string' do
        expect(message.message?).to eq(false)
        message.update! message: string
        expect(message.message).to eq(string)
        expect(message.message?).to eq(true)
        expect(Message.last.message).to eq(string)
        expect(Message.last.encrypted_message).to_not eq(string)

      end

      it 'works with an int' do
        expect(message.message?).to eq(false)
        message.update! message: integer
        expect(message.message).to eq(integer)
        expect(message.message?).to eq(true)
        expect(Message.last.message).to eq(integer)
        expect(Message.last.encrypted_message).to_not eq(integer)
      end

      it 'works with a float' do
        expect(message.message?).to eq(false)
        message.update! message: float
        expect(message.message).to eq(float)
        expect(message.message?).to eq(true)
        expect(Message.last.message).to eq(float)
        expect(Message.last.encrypted_message).to_not eq(float)
      end

      it "works with a hash" do
        expect(message.message?).to eq(false)
        message.update! message: hash
        expect(message.message).to eq(hash)
        expect(message.message?).to eq(true)
        expect(Message.last.message).to eq(hash)
        expect(Message.last.encrypted_message).to_not eq(hash)
      end

      it "works with nil" do
        expect(message.message?).to eq(false)
        message.update! message: nil
        expect(message.message).to eq(nil)
        expect(message.message?).to eq(false)
        expect(Message.last.message).to eq(nil)
        expect(Message.last.encrypted_message).to eq(nil)
      end

      it "doesn't set changed? if assigning same value" do
        message.update! message: string
        message.reload
        message.message = string
        expect(message.changed?).to be false
      end

      it "does set changed? if assigning different value" do
        message.update! message: string
        message.reload
        message.message = string2
        expect(message.changed?).to be true
      end

    end

    describe 'search' do
      it 'works with a string' do
        message.update! message: string
        message2 = Message.create! message: string2

        expect(Message.find_by_message string).to include(message)
        expect(Message.find_by_message string2).to include(message2)
        expect(Message.find_by_message string).to_not include(message2)
      end

      it 'works with a int' do
        message.update! message: integer
        message2 = Message.create! message: integer2

        expect(Message.find_by_message integer).to include(message)
        expect(Message.find_by_message integer2).to include(message2)
        expect(Message.find_by_message integer).to_not include(message2)
      end

      it 'works with a float' do
        message.update! message: float
        message2 = Message.create! message: float2

        expect(Message.find_by_message float).to include(message)
        expect(Message.find_by_message float2).to include(message2)
        expect(Message.find_by_message float).to_not include(message2)
      end

      it 'works with a hash' do
        message.update! message: hash
        message2 = Message.create! message: hash2

        expect(Message.find_by_message hash).to include(message)
        expect(Message.find_by_message hash2).to include(message2)
        expect(Message.find_by_message hash).to_not include(message2)
      end

      it 'works with nil' do
        message.update! message: nil
        message2 = Message.create! message: string2

        expect(Message.find_by_message nil).to include(message)
        expect(Message.find_by_message string2).to include(message2)
        expect(Message.find_by_message nil).to_not include(message2)
      end

      it 'works with a previously added bind param' do
        10.times { Message.new }
        expect{Message.where(flag: true).find_by_message('123121234').present?}.to_not raise_error
      end

      it 'works with a subsequently added bind param' do
        10.times { Message.new }
        expect{Message.find_by_message('123121234').where(flag: true).present?}.to_not raise_error
      end

    end
  end

  ENV_VARS = %w{PGCRYPTO_PUBLIC_KEY PGCRYPTO_PRIVATE_KEY PGCRYPTO_PRIVATE_KEY_PASSWORD PGCRYPTO_SALT}.freeze

  def reset_config_and_env
    ActiveRecord::Pgcrypto.instance_variable_set :@configuration, nil
    ENV_VARS.each{|v| ENV.delete v}
  end

  context 'with a configuration block' do
    context 'a key with a password' do
      before(:all) do
        reset_config_and_env

        ActiveRecord::Pgcrypto.configure do |c|
          c.public_key = PUBLIC_KEY_PASS
          c.private_key = PRIVATE_KEY_PASS
          c.private_key_password = PASSWORD
          c.salt = SALT
        end
      end

      it_behaves_like "attribute encryption"
    end

    context 'a key without a password' do
      before(:all) do
        reset_config_and_env

        ActiveRecord::Pgcrypto.configure do |c|
          c.public_key = PUBLIC_KEY_NO_PASS
          c.private_key = PRIVATE_KEY_NO_PASS
          c.salt = SALT
        end
      end

      it_behaves_like "attribute encryption"
    end
  end

  context 'without a configuration block' do
    before(:all) do
      reset_config_and_env
      ENV['PGCRYPTO_PUBLIC_KEY'] = PUBLIC_KEY_PASS
      ENV['PGCRYPTO_PRIVATE_KEY'] = PRIVATE_KEY_PASS
      ENV['PGCRYPTO_PRIVATE_KEY_PASSWORD'] = PASSWORD
      ENV['PGCRYPTO_SALT'] = SALT
    end

    it_behaves_like "attribute encryption"

    describe '#configuration' do
      it 'works' do
        config = ActiveRecord::Pgcrypto.configuration
        expect(config.public_key).to eq(PUBLIC_KEY_PASS)
        expect(config.private_key).to eq(PRIVATE_KEY_PASS)
        expect(config.private_key_password).to eq(PASSWORD)
        expect(config.salt).to eq(SALT)
      end
    end
  end

end
