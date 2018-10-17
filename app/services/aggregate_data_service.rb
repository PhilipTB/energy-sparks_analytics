# This should take a meter collection and populate
# it with aggregated & validated data
class AggregateDataService
  include Logging

  attr_reader :meter_collection

  def initialize(meter_collection)
    @meter_collection   = meter_collection
    @heat_meters        = @meter_collection.heat_meters.select { |meter| meter.active }
    @electricity_meters = @meter_collection.electricity_meters.select { |meter| meter.active }
  end

  def validate_and_aggregate_meter_data
    logger.info 'Validating and Aggregating Meters'
    validate_meter_data
    aggregate_heat_meters
    create_storage_heater_sub_meters # create before electric aggregation
    create_solar_pv_sub_meters
    aggregate_electricity_meters

    # Return populated with aggregated data
    @meter_collection
  end

  def validate_meter_data
    logger.info 'Validating Meters'
    validate_meter_list(@heat_meters)
    validate_meter_list(@electricity_meters)
  end

  def aggregate_heat_and_electricity_meters
    aggregate_heat_meters
    aggregate_electricity_meters
  end

  private

  def validate_meter_list(list_of_meters)
    logger.info "Validating #{list_of_meters.length} meters"
    list_of_meters.each do |meter|
      validate_meter = ValidateAMRData.new(meter, 50, @meter_collection.holidays, @meter_collection.temperatures)
      validate_meter.validate
    end
  end

  # if the electricity meter has a storage heater, split the meter
  # into 2 one with storage heater only kwh, the other with the remainder
  def create_storage_heater_sub_meters
    @electricity_meters.each do |electricity_meter|
      next if electricity_meter.storage_heater_config.nil?

      logger.info 'Disaggregating electricity meter into 1x storage heater only and 1 x remainder'

      electric_only_amr, storage_heater_amr = electricity_meter.storage_heater_config.disaggregate_amr_data(electricity_meter.amr_data)

      electric_only_meter = create_modified_meter_copy(
        electricity_meter,
        electric_only_amr,
        :electricity,
        electricity_meter.id + ' minus storage heater',
        electricity_meter.name + ' minus storage heater'
      )
      electricity_meter.sub_meters.push(electric_only_meter)

      storage_heater_meter = create_modified_meter_copy(
        electricity_meter,
        storage_heater_amr,
        :storage_heater,
        electricity_meter.id + ' storage heater only',
        electricity_meter.name + ' storage heater only'
      )
      electricity_meter.sub_meters.push(storage_heater_meter)
    end
  end

  # creates artificial PV meters, if solar pv present by scaling
  # 1/2 hour yield data from Sheffield University by the kWp(s) of
  # the PV installation; note the kWh is negative as its a producer
  # rather than a consumer
  def create_solar_pv_sub_meters
    @electricity_meters.each do |electricity_meter|
      next if electricity_meter.solar_pv_installation.nil?

      logger.info 'Creating an artificial solar pv meter and associated amr data'

      solar_amr = create_solar_pv_amr_data(
        electricity_meter.amr_data,
        electricity_meter.solar_pv_installation
      )

      solar_pv_meter = create_modified_meter_copy(
        electricity_meter,
        solar_amr,
        :solar_pv,
        'solarpvid',
        electricity_meter.solar_pv_installation.to_s
      )

      electricity_meter.sub_meters.push(solar_pv_meter)

      # make the original top level meter a sub meter of itself

      original_electric_meter = create_modified_meter_copy(
        electricity_meter,
        electricity_meter.amr_data,
        :electricity,
        electricity_meter.id,
        electricity_meter.name
      )

      electricity_meter.sub_meters.push(original_electric_meter)

      # replace the AMR data of the top level meter with the
      # combined original mains consumption data plus the solar pv data

      electric_plus_pv_amr_data = aggregate_amr_data(
        [electricity_meter.amr_data, solar_amr],
        :electricity
        )

      electricity_meter.amr_data = electric_plus_pv_amr_data
      electricity_meter.id += ' plus pv'
      electricity_meter.name += ' plus pv'
    end
  end

  def create_modified_meter_copy(meter, amr_data, type, identifier, name)
    MeterAnalysis.new(
      meter_collection,
      amr_data,
      type,
      identifier,
      name,
      meter.floor_area,
      meter.number_of_pupils,
      meter.solar_pv_installation,
      meter.storage_heater_config
    )
  end

  def create_solar_pv_amr_data(electricity_amr, solar_pv_installation)
    solar_amr = AMRData.new(:solar_pv)
    (electricity_amr.start_date..electricity_amr.end_date).each do |date|
      if date >= meter_collection.solar_pv.start_date
        scale_factor = solar_pv_installation.capacity_kwp_on_date(date)
        days_pv_yield = meter_collection.solar_pv[date]
        producer = 1.0 # positive kWh despite producer rather than consumer
        scaled_pv_kwh = days_pv_yield.map { |i| i * scale_factor * producer }
        solar_amr.add(date, scaled_pv_kwh)
      end
    end
    logger.info "Created new solar pv meter with #{solar_amr.length} days of data"
    solar_amr
  end

  def aggregate_heat_meters
    @meter_collection.aggregated_heat_meters = aggregate_main_meters(@meter_collection.aggregated_heat_meters, @heat_meters, :gas)
  end

  def aggregate_electricity_meters
    @meter_collection.aggregated_electricity_meters = aggregate_main_meters(@meter_collection.aggregated_electricity_meters, @electricity_meters, :electricity)
  end

  def heating_model(period)
    unless @heating_models.key?(:basic)
      @heating_models[:basic] = AnalyseHeatingAndHotWater::BasicRegressionHeatingModel.new(@aggregated_heat_meters.amr_data, @meter_collection.holidays, @meter_collection.temperatures)
      @heating_models[:basic].calculate_regression_model(period)
    end
    # PH 21Jun2016 - commented this back in
    # logger.debug "Calculating model 21Jun18 debug", @period.inspect
    @heating_on_periods = @model.calculate_heating_periods(@period)
    @heating_models[:basic]
  end

  def aggregate_amr_data(meters, type)
    if meters.length == 1
      logger.info "Single meter, so aggregation is a reference to itself not an aggregate meter"
      return meters.first.amr_data # optimisaton if only 1 meter, then its its own aggregate
    end
    min_date, max_date = combined_amr_data_date_range(meters)
    logger.info "Aggregating data between #{min_date} #{max_date}"

    mpan_mprn = 'NEEDSFIXING'
    mpan_mprn = MeterAnalysis.synthetic_combined_meter_mpan_mprn_from_urn(@meter_collection.urn, meters[0].fuel_type) unless @meter_collection.urn.nil?
    combined_amr_data = AMRData.new(type)
    (min_date..max_date).each do |date|
      combined_data = Array.new(48, 0.0)
      meters.each do |meter|
        (0..47).each do |half_hour_index|
          if meter.amr_data.key?(date)
            combined_data[half_hour_index] += meter.amr_data.kwh(date, half_hour_index)
          end
        end
      end
      days_data = OneDayAMRReading.new(mpan_mprn, date, 'ORIG', nil, DateTime.now, combined_data)
      combined_amr_data.add(date, days_data)
    end
    combined_amr_data
  end

  def combine_meter_meta_data(list_of_meters)
    meter_names = []
    ids = []
    floor_area = 0
    pupils = 0
    list_of_meters.each do |meter|
      meter_names.push(meter.name)
      ids.push(meter.id)
      if !floor_area.nil? && !meter.floor_area.nil?
        floor_area += meter.floor_area
      else
        floor_area = nil
      end
      if !pupils.nil? && !meter.number_of_pupils.nil?
        pupils += meter.number_of_pupils
      else
        pupils = nil
      end
    end
    name = meter_names.join(' + ')
    id = ids.join(' + ')
    [name, id, floor_area, pupils]
  end

  def aggregate_main_meters(combined_meter, list_of_meters, type)
    logger.info "Aggregating #{list_of_meters.length} meters"
    combined_meter = aggregate_meters(combined_meter, list_of_meters, type)
    combine_sub_meters(combined_meter, list_of_meters)
    combined_meter
  end

  def aggregate_meters(combined_meter, list_of_meters, type)
    return nil if list_of_meters.nil? || list_of_meters.empty?
    if list_of_meters.length == 1
      logger.info "Single meter of type #{type} - using as combined meter rather than creating new one"
      return list_of_meters.first
    end

    log_meter_dates(list_of_meters)

    combined_amr_data = aggregate_amr_data(list_of_meters, type)

    combined_name, combined_id, combined_floor_area, combined_pupils = combine_meter_meta_data(list_of_meters)

    if combined_meter.nil?
      combined_meter = MeterAnalysis.new(
        self,
        combined_amr_data,
        type,
        combined_id,
        combined_name,
        combined_floor_area,
        combined_pupils
      )
    else
      logger.info "Combined meter #{combined_meter.mpan_mprn} already created"
      combined_meter.floor_area = combined_floor_area if combined_meter.floor_area.nil? || combined_meter.floor_area == 0
      combined_meter.number_of_pupils = combined_pupils if combined_meter.number_of_pupils.nil? || combined_meter.number_of_pupils == 0
      combined_meter.amr_data = combined_amr_data
    end

    logger.info "Creating combined meter data #{combined_amr_data.start_date} to #{combined_amr_data.end_date}"
    logger.info "with floor area #{combined_floor_area} and #{combined_pupils} pupils"
    combined_meter
  end

  def log_meter_dates(list_of_meters)
    logger.info 'Combining the following meters'
    list_of_meters.each do |meter|
      MeterAttributes.attributes(meter, :aggregation)
      logger.info sprintf('%-24.24s %-18.18s %s to %s', meter.display_name, meter.id, meter.amr_data.start_date.to_s, meter.amr_data.end_date)
      aggregation_rules = MeterAttributes.attributes(meter, :aggregation)
      unless aggregation_rules.nil?
        logger.info "                Meter has aggregation rules #{aggregation_rules}"
      end
    end
  end

  def group_sub_meters_by_fuel_type(list_of_meters)
    sub_meter_types = {}
    list_of_meters.each do |meter|
      meter.sub_meters.each do |sub_meter|
        fuel_type = meter.fuel_type
        sub_meter_types[fuel_type] = [] unless sub_meter_types.key?(fuel_type)
        sub_meter_types[fuel_type].push(sub_meter)
      end
    end
    sub_meter_types
  end

  def combine_sub_meters(parent_meter, list_of_meters)
    sub_meter_types = group_sub_meters_by_fuel_type(list_of_meters)

    sub_meter_types.each do |fuel_type, sub_meters|
      combined_meter = aggregate_meters(sub_meters, fuel_type)
      parent_meter.sub_meters.push(combined_meter)
    end
  end

  # for overlapping data i.e. date range where there is data for all meters
  def combined_amr_data_date_range(meters)
    start_dates = []
    end_dates = []
    meters.each do |meter|
      aggregation_rules = MeterAttributes.attributes(meter, :aggregation)
      if aggregation_rules.nil?
        start_dates.push(meter.amr_data.start_date)
      elsif !(aggregation_rules.include?(:ignore_start_date) ||
              aggregation_rules.include?(:deprecated_include_but_ignore_start_date))
        start_dates.push(meter.amr_data.start_date)
      end
      if aggregation_rules.nil?
        end_dates.push(meter.amr_data.end_date)
      elsif !(aggregation_rules.include?(:ignore_end_date) ||
        aggregation_rules.include?(:deprecated_include_but_ignore_end_date))
        end_dates.push(meter.amr_data.end_date)
      end
    end
    [start_dates.sort.last, end_dates.sort.first]
  end
end
