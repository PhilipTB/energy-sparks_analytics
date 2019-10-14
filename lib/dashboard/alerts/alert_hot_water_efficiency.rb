#======================== Hot Water Efficiency =================================
require_relative 'alert_gas_model_base.rb'

class AlertHotWaterEfficiency < AlertGasModelBase
  attr_reader :investment_choices_table, :daytype_breakdown_table

  def initialize(school)
    super(school, :hotwaterefficiency) 
    @relevance = :never_relevant if @relevance != :never_relevant && heating_only # set before calculation
  end

  def timescale
    'year'
  end

  def enough_data
    hw_model = AnalyseHeatingAndHotWater::HotwaterModel.new(@school)
    summer_holidays = hw_model.find_period_before_and_during_summer_holidays(@school.holidays, aggregate_meter.amr_data)
    summer_holidays.nil? ? :not_enough : :enough 
  end

  def self.template_variables
    vars = {'Hot water efficiency' => TEMPLATE_VARIABLES}
    vars.merge!({'Investment table variables' => HotWaterInvestmentAnalysisText.investment_table_template_variables})
    vars.merge!({'Day type breakdown table variables' => HotWaterInvestmentAnalysisText.daytype_table_template_variables})
    vars.merge(self.superclass.template_variables)
  end

  TEMPLATE_VARIABLES = {
    summer_hot_water_efficiency_chart: {
      description: 'Chart of summer gas consumption before and during summer holidays',
      units: :chart
    },
    investment_choices_table: {
      description: 'Current v. Improved Control v. Point of Use Electric cost-benefit table',
      units: :table,
      header: ['Choice', 'Annual kWh', 'Annual Cost £', 'Annual CO2/kg',
               'Efficiency', 'Saving £', 'Saving £ percent', 'Saving CO2', 
               'Saving CO2 percent', 'Capital Cost', 'Payback (years)'],
      column_types: [String, {kwh: :gas}, :£, :co2,
                      :percent, :£, :percent, :co2,
                      :percent, :£, :years],
      data_column_justification: %i[left right right right right right right right right right right]
    },
    daytype_breakdown_table: {
      description: 'School day open v. School day closed v Holidays v Weekends kWh/£ usage',
      units: :table,
      header: ['', 'Average daily kWh', 'Average daily £', 'Annual kWh', 'Annual £'],
      column_types: [String, {kwh: :gas}, :£, {kwh: :gas}, :£],
      data_column_justification: %i[left right right right right]
    },
  }

  def summer_hot_water_efficiency_chart
    :hotwater_alert
  end

  # higher rating in summer when user has time to think about hot water versus heating
  def time_of_year_relevance
    set_time_of_year_relevance(@heating_on.nil? ? 5.0 : (@heating_on ? 5.0 : 7.5))
  end

  private def calculate(asof_date)
    calculate_model(asof_date) # so gas_model_only base varaiables are expressed even if no hot water
    if @relevance != :never_relevant && heating_only
      @relevance = :never_relevant
      @rating = nil
    else
      investment = HotWaterInvestmentAnalysisText.new(@school)
      set_tabular_data_as_dynamically_created_attributes(investment.alert_table_data)
      header, rows, totals = investment.investment_table(nil)
      @investment_choices_table = rows

      header, rows, totals = investment.daytype_breakdown_table(nil)
      @daytype_breakdown_table = rows

      @relevance = :relevant

      one_year_saving_£ = one_year_saving_calculation
      capital_costs_£ = @existing_gas_capex..@point_of_use_electric_capex
      set_savings_capital_costs_payback(one_year_saving_£, electric_point_of_use_hotwater_costs)

      @rating = calculate_rating_from_range(0.6, 0.05, @existing_gas_efficiency)

      @term = :shortterm
      @bookmark_url = add_book_mark_to_base_url('HotWaterEfficiency')
    end
  end
  alias_method :analyse_private, :calculate

  private def one_year_saving_calculation
    savings = [@gas_better_control_saving_£, @point_of_use_electric_saving_£].sort
    savings[0]..savings[1]
  end

  private def set_tabular_data_as_dynamically_created_attributes(data)
    data.each do |key, value|
      create_and_set_attr_reader(key, value)
    end
  end

  private def create_and_set_attr_reader(key, value)
    self.class.send(:attr_reader, key)
    instance_variable_set("@#{key}", value)
  end
end
