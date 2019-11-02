require_relative './alert_storage_heater_mixin.rb'
require_relative './alert_thermostatic_control.rb'

class AlertStorageHeaterAnnualVersusBenchmark < AlertGasAnnualVersusBenchmark
  include AlertGasToStorageHeaterSubstitutionMixIn
  def initialize(school)
    super(school, :storage_heater_annual_benchmark)
    @relevance = @school.storage_heaters? ? :relevant : :never_relevant 
  end
end

class AlertStorageHeaterThermostatic < AlertThermostaticControl
  include AlertGasToStorageHeaterSubstitutionMixIn
  def initialize(school)
    super(school, :storage_heater_thermostatic)
    @relevance = @school.storage_heaters? ? :relevant : :never_relevant 
  end

  def thermostatic_chart
    :storage_heater_thermostatic
  end
end

class AlertStorageHeaterOutOfHours < AlertOutOfHoursGasUsage
  include AlertGasToStorageHeaterSubstitutionMixIn
  def initialize(school)
    super(school, 'electricity', BenchmarkMetrics::PERCENT_STORAGE_HEATER_OUT_OF_HOURS_BENCHMARK,
          BenchmarkMetrics::ELECTRICITY_PRICE, :storageheateroutofhours,
          '', :allstorageheater, 0.2, 0.5)
    @relevance = @school.storage_heaters? ? :relevant : :never_relevant 
  end

  def breakdown_chart
    :alert_daytype_breakdown_storage_heater
  end

  def group_by_week_day_type_chart
    :alert_group_by_week_storage_heaters
  end
end

class AlertHeatingOnSchoolDaysStorageHeaters < AlertHeatingOnSchoolDays
  include AlertGasToStorageHeaterSubstitutionMixIn
  def initialize(school)
    super(school, :storage_heater_heating_days)
    @relevance = @school.storage_heaters? ? :relevant : :never_relevant 
  end

  def heating_on_off_chart
    :heating_on_by_week_with_breakdown_storage_heaters
  end
end

