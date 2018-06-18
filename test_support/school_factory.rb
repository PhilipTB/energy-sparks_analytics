# School Factory: deals with getting school, meter data from different sources:
# - Verco Energy Survey 2013:   240 meters, 70 schools from Excel files
#                               1 workbook per school, 1 sheet per meter
# - Bath: Hacked CSV download:  2 workbooks: 1 x gas, 1 x electric, 1 sheet per school
# - Bath: Hacked Socrata/YAML:  direct download from Bath: Hacked datastore with YAML caching
#
# - source of data currently controlled by Environment Variables ENV[......]
#
# - the aim is to largely lazy load data on demand
#

require_relative 'load_amr_from_bath_hacked'

class SchoolFactory
  BATH_HACKED_SCHOOL_DATA = 'bath:hacked'.freeze
  EXCEL_SCHOOL_DATA = 'excel'.freeze
  ENV_SCHOOL_DATA_SOURCE = 'ENERGYSPARKSDATASOURCE'.freeze

  def initialize
    @school_cache = {
      BATH_HACKED_SCHOOL_DATA => {}, # school name to school
      EXCEL_SCHOOL_DATA => {} # school name to school
    }
    @backhacked_school_definitions = nil
  end

  # creates a 'school' by loading data from a source of data (socrata, excel etc.)
  # defined by environment variable ENV_SCHOOL_DATA_SOURCE
  def load_school(identifier, validate_and_aggregate = true)
    if identifier.is_a?(String) # reference by name
      source = ENV[ENV_SCHOOL_DATA_SOURCE]

      if @school_cache[source].key?(identifier)
        @school_cache[source][identifier]
      elsif source == BATH_HACKED_SCHOOL_DATA
        @school_cache[source][identifier] = load_data_from_back_hacked(identifier, validate_and_aggregate)
      elsif source == EXCEL_SCHOOL_DATA
        @school_cache[source][identifier] = load_data_from_excel(identifier, validate_and_aggregate)
      else
        raise 'Error: ENV_SCHOOL_DATA_SOURCE not set so cant load school/meter data' if source.nil?
        raise "Error: ENV_SCHOOL_DATA_SOURCE set to unknown value #{source}"
      end
    else
      raise 'Error: Attempt to load school by nil identifier' if identifier.nil?
      raise "Error: Attempt to load school not using name but #{identifier.class.name}"
    end
  end

  def load_data_from_back_hacked(school_name, validate_and_aggregate)
    @backhacked_school_definitions = LoadSchools.new if @backhacked_school_definitions.nil?
    min_date = Date.new(2013, 9, 1)
    school_as_meter_collection = @backhacked_school_definitions.load_school(school_name, min_date, true)

    if validate_and_aggregate
      # Get the school data, validate and aggregate the meter data
      AggregateDataService.new(school_as_meter_collection).validate_and_aggregate_meter_data
    else
      # This is a school wrapped as a meter collection, without aggregated data
      school_as_meter_collection
    end
  end

  def load_data_from_excel(school_name, validate_and_aggregate)
    school = school.new(school_name)
    loader = LoadMeterDataFromCSV.new(school)
    loader.load_meters
    if validate_and_aggregate
      school.validate_and_aggregate_meter_data
    end
    school
  end
end