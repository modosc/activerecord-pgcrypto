$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'active_record'
require 'active_record/pgcrypto'
require 'faker'

LOG_FILE = File.expand_path('../../log/test.log', __FILE__)
FileUtils.mkdir_p File.dirname LOG_FILE
ActiveRecord::Base.logger = Logger.new(LOG_FILE)
