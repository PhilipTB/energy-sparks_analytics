# maintains history of alerts in CSV file format
# - used for historical analytics
# - for testing purposes - comparing with previous runs of the alerts
#

class BenchmarkDatabase
  attr_reader :db_filename, :database

  def initialize(filename)
    @db_filename = filename
    @database = {}
    load_database
  end

  def add_value(date, urn, alert_short_code, value_short_code, value)
    var_key = alert_short_code + '_' + value_short_code

    begin
      add_create(date, urn, var_key, value)
    rescue StandardError => e
      puts e.message
      puts "Got here 2 #{date} #{urn} #{alert_short_code} #{value_short_code} #{value}"
    end
  end

  private def add_create(date, urn, key, value)
    @database[date] ||= {}
    @database[date][urn] ||= {}
    @database[date][urn][key] = value
  end

  def save_database(data = database)
    if database.empty?
      puts 'Unable to save: database empty'
    else
      # data_without_default_proc = remove_proc_from_hash(data.deep_dup)
      writer = FileWriter.new(@db_filename)
      writer.save(data)
    end
  end

  def remove_proc_from_hash(hash, set = false) # as marshal can't dump default procs
    hash.default_proc = set ? {} : nil
    hash.each do |key, value|
      remove_proc_from_hash(value, set) if value.is_a?(Hash)
    end
  end

  private def load_database
    writer = FileWriter.new(@db_filename)
    data = writer.load
    @database.deep_merge!(data) unless data.nil?
  end
end
