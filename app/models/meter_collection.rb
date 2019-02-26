# Was a building!

# building: potentially a misnomer, holds data associated with a group
#           of buildings, which could be a whole school or the area
#           covered by a single meter
#           primarily a placeholder for data associated with a school
#           or group of buildings, potentially different to the parent
#           school, so for example a different holiday and open/close time
#           schedule if a meter covers a community sports centre which is
#           used out of core school hours
#           - also holds modelling data

class MeterCollection
  include Logging

  attr_reader :heat_meters, :electricity_meters, :solar_pv_meters, :storage_heater_meters

  # From school/building
  attr_reader :floor_area, :number_of_pupils

  # Currently, but not always
  attr_reader :school, :name, :address, :postcode, :urn, :area_name

  # These are things which will be populated
  attr_accessor :aggregated_heat_meters, :aggregated_electricity_meters, :heating_models, :electricity_simulation_meter

  def initialize(school, meter_attributes = MeterAttributes)
    @name = school.name
    @address = school.address
    @postcode = school.postcode
    @floor_area = school.floor_area
    @number_of_pupils = school.number_of_pupils
    @heat_meters = []
    @electricity_meters = []
    @solar_pv_meters = []
    @storage_heater_meters = []
    @heating_models = {}
    @school = school
    @urn = school.urn
    @meter_identifier_lookup = {} # [mpan or mprn] => meter
    @area_name = school.area_name
    @aggregated_heat_meters = nil
    @aggregated_electricity_meters = nil
    @meter_attributes = meter_attributes

    @cached_open_time = TimeOfDay.new(7, 0) # for speed
    @cached_close_time = TimeOfDay.new(16, 30) # for speed

    if Object.const_defined?('ScheduleDataManager')
      logger.info 'Running standalone, not in Rails environment'

      # Normally these would come from the school, hard coded at the mo
      @holiday_schedule_name = school.area_name.nil? ? ScheduleDataManager::BATH_AREA_NAME : school.area_name
      @temperature_schedule_name = school.area_name.nil? ? ScheduleDataManager::BATH_AREA_NAME : school.area_name
      @solar_irradiance_schedule_name = school.area_name.nil? ? ScheduleDataManager::BATH_AREA_NAME : school.area_name
      @solar_pv_schedule_name = school.area_name.nil? ? ScheduleDataManager::BATH_AREA_NAME : school.area_name
    else
      logger.info 'Running in Rails environment'
      throw ArgumentException if school.meters.empty?
    end
  end

  def matches_identifier?(identifier, identifier_type)
    case identifier_type
    when :name
      identifier == name
    when :urn
      identifier == urn
    when :postcode
      identifier == postcode
    else
      throw EnergySparksUnexpectedStateException.new("Unexpected nil school identifier_type") if identifier_type.nil?
      throw EnergySparksUnexpectedStateException.new("Unknown or implement school identifier lookup #{identifier_type}")
    end
  end

  def to_s
    'Meter Collection:' + name + ':' + all_meters.join(';')
  end

  def meter?(identifier)
    return @meter_identifier_lookup[identifier] if @meter_identifier_lookup.key?(identifier)

    all_meters.each do |meter|
      if meter.id == identifier
        @meter_identifier_lookup[identifier] = meter
        return meter
      end
    end
    @meter_identifier_lookup[identifier] = nil
  end

  def all_meters
    meter_groups = [
      @heat_meters,
      @electricity_meters,
      @solar_pv_meters,
      @storage_heater_meters,
      @aggregated_heat_meters,
      @aggregated_electricity_meters
    ]

    meter_list = []
    meter_groups.each do |meter_group|
      unless meter_group.nil?
        meter_list += meter_group.is_a?(Dashboard::Meter) ? [meter_group] : meter_group
      end
    end
    meter_list
  end

  def school_type
    @school.nil? ? nil : @school.school_type
  end

  def add_heat_meter(meter)
    @heat_meters.push(meter)
    @meter_identifier_lookup[meter.id] = meter
  end

  def add_electricity_meter(meter)
    @electricity_meters.push(meter)
    @meter_identifier_lookup[meter.id] = meter
  end

  def add_aggregate_heat_meter(meter)
    @aggregated_heat_meters = meter
    @meter_identifier_lookup[meter.id] = meter
  end

  def add_aggregate_electricity_meter(meter)
    @aggregated_electricity_meters = meter
    @meter_identifier_lookup[meter.id] = meter
  end

  # This is overridden in the energysparks code at the moment, to use the actual open/close times
  # It replaces school_day_in_hours(time_of_day)
  def is_school_usually_open?(_date, time_of_day)
    time_of_day >= @cached_open_time && time_of_day < @cached_close_time
  end

  # held at building level as a school building e.g. a community swimming pool may have a different holiday schedule
  def holidays
    ScheduleDataManager.holidays(@holiday_schedule_name)
  end

  def temperatures
    ScheduleDataManager.temperatures(@temperature_schedule_name)
  end

  def solar_irradiation
    ScheduleDataManager.solar_irradiation(@solar_irradiance_schedule_name)
  end

  def solar_pv
    ScheduleDataManager.solar_pv(@solar_pv_schedule_name)
  end

  def grid_carbon_intensity
    ScheduleDataManager.uk_grid_carbon_intensity
  end

  def heating_model(period)
    # This is a temporary fix until the ES codebase comes in line with the MeterAttributes change TODO: JJ
    @meter_attributes = MeterAttributes if @meter_attributes.nil?
    unless @heating_models.key?(:basic)
      @heating_models[:basic] = AnalyseHeatingAndHotWater::BasicRegressionHeatingModel.new(@aggregated_heat_meters, holidays, temperatures, @meter_attributes)
      @heating_models[:basic].calculate_regression_model(period)
    end
    @heating_models[:basic]
    #  @heating_on_periods = @model.calculate_heating_periods(@period)
  end
end
