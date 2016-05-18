require 'rails/generators'
module ActiveRecord::Pgcrypto
  class PgcryptoMigrationGenerator < Rails::Generators::NamedBase
    argument :attributes, :type => :array, :default => [], :banner => "attribute1 (attribute2 atribute3 ...)"

    source_root File.expand_path('../templates', __FILE__)

    desc "This generator adds one or more encrypted attributes to a given model"

    def migration_number
      @migration_number ||= ActiveRecord::Migration.next_migration_number(0)
    end

    def next_migration_number
      @migration_number = if @migration_number
                              (@migration_number.to_i + 1).to_s
                            else
                              ActiveRecord::Migration.next_migration_number(0)
                            end
      end

      def needs_extension?
        ActiveRecord::Base.extension_enabled? 'pgcrypto'
      end

      def add_encrypted_attribute_to_model
        # first, generate a db migration
        migration_file = File.join 'db/migrate',
          next_migration_number + "_add_encrypted_#{attributes_names.join('_')}_to_#{plural_name}.rb"
        migration = "class AddEncrypted#{attributes_names.join('_').classify}To#{class_name.pluralize} < ActiveRecord::Migration
      def change\n"

        (migration << "    enable_extension 'pgcrypto') if needs_extension?
        # add columns for each of our cli specified attributes
        # TODO - make searchable optional
        attributes_names.each do |n|
          migration << "    add_column :#{plural_name}, :encrypted_#{n}, :text\n"
          migration << "    add_column :#{plural_name}, :hashed_#{n}, :text, index: true\n"
        end

        migration << "  end\nend\n"

        create_file migration_file, migration

        # check and see if we need to migrate from an unencrypted version of this
        # attribute - if so an extra migration is created which moves the old value
        # (:foo) into (:encrypted_foo) and removes the :foo column
        attributes_names.each do |n|
          if Object.const_get(class_name.singularize).attribute_names.include? n
            migration_file =  File.join 'db/migrate',
            next_migration_number + "_migrate_#{n}_to_encrypted_#{n}_in_#{plural_name}.rb"
            create_file migration_file, <<-RUBY
    class Migrate#{n.classify}ToEncrypted#{n.classify}In#{class_name.pluralize} < ActiveRecord::Migration
      def up
        #{class_name.singularize}.where.not(#{n}: nil).find_each do |m|
          dec = m.read_attribute :#{n}
          m.#{n} = dec
          enc = m.read_attribute :encrypted_#{n}
          m.update_column :encrypted_#{n}, enc
        end
        remove_column :#{plural_name}, :#{n}
      end

      # TODO - down is really only good for testing
      def down
        add_column :#{plural_name}, :#{n}, :string

        #{class_name.singularize}.reset_column_information

        #{class_name.singularize}.where.not("encrypted_#{n}".to_sym => nil).find_each do |m|
          m.update_column :#{n}, m.#{n}
        end
      end
    end
    RUBY

          end
        end

        # next, include the AttributeEncryption concern in our model if it's not there
        # already
        model_file =  "app/models/#{plural_name.singularize}.rb"
        if File.readlines(Rails.root.join model_file).grep(/AttributeEncryption/).any?
          gsub_file model_file, /has_encrypted_attributes (.*?)$/,
            "has_encrypted_attributes \\1, #{attributes_names.map{|a| ':' + a}.join(', ')}"
        else
          inject_into_file model_file, after: "class #{class_name.singularize} < ActiveRecord::Base\n" do <<-"RUBY"
      include AttributeEncryption
      has_encrypted_attributes #{attributes_names.map{|a| ":#{a}"}.join(', ')}
    RUBY
          end
        end
      end
    end
  end
end
