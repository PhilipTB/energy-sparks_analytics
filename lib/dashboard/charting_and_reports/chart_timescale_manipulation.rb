# Chart Timescale Management - manages interactive manipulation of chart timescales
#
# - take an existing chart, and allows:
#   - 'move'      - move whole chart  1 time period               (forward or back)
#   - 'extend'    - extend time period of x-axis by 1 time period (forward or back)
#   - 'contract'  - contract time period of x-axis by 1 time period (forward or back)
#   - 'compare'   - compare with adjascent time period            (forward or back)
#
# timescales are defined as:
#   - no timescale as in the benchmark chart - this can't be manipulated
#   - timescale:        :year                       - a symbol
#   - timescale:        { week: -1..0 },            - a hash
#   - timescale:        [{ day: -6...0 }]           - an array
#   - timescale:        [{ year: 0 }, { year: -1 }] - an array
class ChartManagerTimescaleManipulation
  include Logging

  def initialize(type, original_chart_config, school)
    @type = type
    @original_chart_config = original_chart_config.deep_dup
    @school = school
    @cadence_days = nil
    logger.info "Creating time shift manipulator of type #{type}"
  end

  def self.factory(type, original_chart_config, school)
    case type
    when :move;     ChartManagerTimescaleManipulationMove.new(:move, original_chart_config, school)
    when :extend;   ChartManagerTimescaleManipulationExtend.new(:extend, original_chart_config, school)
    when :contract; ChartManagerTimescaleManipulationContract.new(:contract, original_chart_config, school)
    when :compare;  ChartManagerTimescaleManipulationCompare.new(:compare, original_chart_config, school)
    else
      raise EnergySparksUnexpectedStateException, 'Unexpected nil chart adjustment timescale shift' if type.nil?
      raise EnergySparksUnexpectedStateException, "Unexpected chart adjustment timescale shift #{type}"
    end
  end

  def adjust_timescale(factor)
    adjust_timescale_private(factor)
  end

  def can_go_forward_in_time_one_period?
    enough_data?(1)
  end

  def can_go_back_in_time_one_period?
    enough_data?(-1)
  end

  def chart_suitable_for_timescale_manipulation?
    return false unless @original_chart_config.key?(:timescale) && !@original_chart_config[:timescale].nil? # :benchmark type chart has no defined timescale
    timescale_type, value = timescale_type(@original_chart_config)
    !%i[hotwater none].include?(timescale_type)
  end

  def enough_data?(factor)
    begin
      adjust_timescale_private(factor)
      true
    rescue EnergySparksNotEnoughDataException => _e
      false
    rescue
      raise
    end
  end

  def timescale_shift_description(shift_amount)
    return 'no shift' if shift_amount == 0
    direction_description = shift_amount > 0 ? 'forward' : 'back'
    singular_plural = shift_amount.magnitude > 1 ? 's' : '' 
    "#{direction_description} #{shift_amount.magnitude} #{timescale_description}#{singular_plural}"
  end

  protected

  def adjust_timescale_private(factor)
    new_config = @original_chart_config.deep_dup
    logger.info "Old timescales #{new_config[:timescale]}"

    available_periods = available_periods(new_config)
    logger.info "#{available_periods} periods available for chart time manipulation"

    timescales = convert_timescale_to_array(new_config)
    new_timescales = timescale_adjust(timescales, factor, available_periods)

    logger.info "New timescales #{new_timescales}"

    new_config[:timescale] = new_timescales
    new_config[:cadence_days] = @cadence_days unless @cadence_days.nil?
    new_config
  end

  def is_thermostatic_chart?(chart_config)
    chart_config[:chart1_type] == :scatter &&
    chart_config[:series_breakdown].length == 2 &&
    (chart_config[:series_breakdown] & %i[model_type temperature]).length == 2
  end

  def manipulate_timescale(timescale, factor, available_periods)
    raise EnergySparksAbstractBaseClass, 'attempt to call abstract base class for time manipulation'
  end

  def timescale_adjust(timescales, factor, available_periods)
    new_timescales = []
    timescales.each do |timescale|
      new_timescales.push(manipulate_timescale(timescale, factor, available_periods))
    end
    new_timescales
  end

  private def determine_chart_range(chart_config)
    aggregator = Aggregator.new(@school, chart_config, false)
    chart_config, _schools = aggregator.initialise_schools_date_range # get min and max combined meter ranges
    if chart_config.key?(:min_combined_school_date) || chart_config.key?(:max_combined_school_date)
      logger.info "METER range = #{chart_config[:min_combined_school_date]} to #{chart_config[:max_combined_school_date]}"
      [chart_config[:min_combined_school_date], chart_config[:max_combined_school_date]]
    else
      raise EnergySparksUnexpectedStateException, 'Unable to determine chart date range'
    end
  end

  def convert_timescale_to_array(chart_config)
    convert_timescale_to_array_internal(chart_config[:timescale])
  end

  protected def convert_timescale_to_array_internal(timescale)
    timescales = []
    if timescale.is_a?(Symbol)
      timescales = [ {timescale => 0}]
    elsif timescale.is_a?(Hash)
      timescales = [ timescale ]
    elsif timescale.is_a?(Array)
      timescales = timescale
    else
      raise EnergySparksUnexpectedStateException, "Unsupported timescale #{timescale} for chart manipulation"
    end
    timescales
  end

  TIME_SCALE_TYPES = { 
    year:           'year',
    academicyear:   'academic year',
    month:          'month',
    holiday:        'holiday',
    includeholiday: 'holiday',
    week:           'week',
    workweek:       'week',
    schoolweek:     'school week',
    day:            'day',
    frostday:       'frosty day',
    frostday_3:     'frosty day',
    diurnal:        'day with large diurnal range',
    optimum_start:  'optimum start example day',
    daterange:      'date range',
    hotwater:       'summer period with hot water usage',
    none:           ''
  }.freeze

  def self.timescale_name(timescale_symbol) # also used by drilldown
    TIME_SCALE_TYPES.key?(timescale_symbol) ? TIME_SCALE_TYPES[timescale_symbol] : TIME_SCALE_TYPES[:none] 
  end

  public def timescale_description
    timescales = convert_timescale_to_array_internal(@original_chart_config[:timescale])
    timescale = timescales[0]
    if timescale.is_a?(Hash) && !timescale.empty? && timescale.keys[0] == :daterange
      impute_description_from_date_range(timescale.values[0])
    elsif TIME_SCALE_TYPES.key?(timescale)
      self.class.timescale_name(timescale)
    elsif timescale.is_a?(Hash) && !timescale.empty? && TIME_SCALE_TYPES.key?(timescale.keys[0])
      self.class.timescale_name(timescale.keys[0])
    else
      'period'
    end
  end

  private

  private def impute_description_from_date_range(date_range)
    days = days_in_date_range(date_range)
    case days
    when 1
      self.class.timescale_name(:day)
    when 7
      self.class.timescale_name(:week)
    when 28..31
      self.class.timescale_name(:month)
    when 350..380
      self.class.timescale_name(:year)
    else
      if days % 7 == 0
        "#{days / 7} weeks" # ends up with duplicate number e.g. 'Move forward 1 2 weeks' TODO(PH, 13Sep2019) fix further up hierarchy
      else
        self.class.timescale_name(:daterange)
      end
    end
  end

  def available_periods(chart_config_original = @original_chart_config)
    available_periods_by_type(chart_config_original)
  end

  private def available_periods_by_type(chart_config_original)
    start_date, end_date = determine_chart_range(chart_config_original)
    timescale_type, value = timescale_type(chart_config_original)
    case timescale_type
    when :year
      ((end_date - start_date + 1) / 365.0).floor
    when :academicyear
      @school.holidays.academic_years(start_date, end_date).length
    when :workweek
      start_date = start_date - ((start_date.wday - 6) % 7)
      ((end_date - start_date + 1) / 7.0).floor
    when :week
      ((end_date - start_date + 1) / 7.0).floor
    when :schoolweek
      _sunday, _saturday, week_count = @school.holidays.nth_school_week(end_date, -1000, 3, start_date)
      1000 - week_count
    when :day, :datetime
      end_date - start_date + 1
    when :month
      (end_date.year * 12 + end_date.month - 1) - (start_date.year * 12 + start_date.month - 1) + 1
    when :holiday
      @school.holidays.number_holidays_between_dates(start_date, end_date, false)
    when :includeholiday
      @school.holidays.number_holidays_between_dates(start_date, end_date, true)
    when :frostday, :frostday_3
      @school.temperatures.frost_days(start_date, end_date, 0, @school.holidays).length
    when :diurnal
      @school.temperatures.largest_diurnal_ranges(start_date, end_date, true, false, @school.holidays, false).length
    when :optimum_start
      OptimumStartPeriods::BEST_OPTIMUM_START_DAYS.length
    when :daterange
      days_in_range = value.last - value.first + 1
      ((end_date - start_date + 1) / days_in_range).floor
    when :hotwater
      raise EnergySparksUnexpectedStateException, 'Hot water chart timescale manipulation currently not supported'
    when :none
      raise EnergySparksUnexpectedStateException, 'None timescale manipulation currently not supported'
    else
      raise EnergySparksUnexpectedStateException, "Unsupported period type #{timescale_type} for periods_in_date_range request"
    end
  end

  def timescale_type(chart_config_original)
    timescale = chart_config_original[:timescale]
    if timescale.is_a?(Symbol)
      [timescale, 0]
    elsif timescale.is_a?(Array) && timescale[0].is_a?(Hash)
      key, value = timescale[0].first
      [key, value]
    elsif timescale.is_a?(Hash)
      key, value = timescale.first
      [key, value]
    else
      raise EnergySparksUnexpectedStateException, "Unsupported timescale type for chart timescale manipulation #{timescale} #{timescale.class.name}"
    end
  end

  def calculate_new_period_number(period_number, factor, available_periods)
    new_period_number = period_number + factor
    if new_period_number > 0 || new_period_number < (-1 * (available_periods - 1))
      raise EnergySparksNotEnoughDataException, "Timescale charge request out of range #{new_period_number} versus #{available_periods} limit"
    end
    new_period_number
  end

  def date_range?(range)
    range.first.is_a?(Date) && range.last.is_a?(Date)
  end

  def calculate_new_date_range(existing_timescale_daterange, start_factor, end_factor, override_days_factor = nil)
    days_in_range = override_days_factor.nil? ? days_in_date_range(existing_timescale_daterange) : override_days_factor
    # need to provide chart config for original period range, so when you extend.
    # from a 1 to a 2 and then a 3 week chart, you can go back to a 2 week chart following a contraction request
    @cadence_days = days_in_range.to_i unless @original_chart_config.key?(:cadence_days)
    start_date = existing_timescale_daterange.first + days_in_range * start_factor
    end_date = existing_timescale_daterange.last + days_in_range * end_factor
    available_data_start_date, available_data_end_date = determine_chart_range(@original_chart_config)
    raise EnergySparksNotEnoughDataException, "Not enough data available earliest available data #{available_data_start_date} request #{start_date}" if start_date < available_data_start_date
    raise EnergySparksNotEnoughDataException, "Not enough data available latest available data #{available_data_end_date} request #{end_date}" if end_date > available_data_end_date
    Range.new(start_date, end_date, existing_timescale_daterange.exclude_end?)
  end

  def calculate_new_period_range(existing_period, start_factor, end_factor)
    new_end_period_number = calculate_new_period_number(existing_period.last, end_factor, available_periods)
    new_start_period_number = calculate_new_period_number(existing_period.first, start_factor, available_periods)
    Range.new(new_start_period_number, new_end_period_number, existing_period.exclude_end?)
  end

  def calculate_new_range(period_type, existing_range, start_factor, end_factor, override_days_factor = nil, requires_cadence = false)
    if date_range?(existing_range)
      raise EnergySparksNotEnoughDataException, 'Cant contract chart without previously extended cadence information' if requires_cadence && !@original_chart_config.key?(:cadence_days)
      { period_type => calculate_new_date_range(existing_range, start_factor, end_factor, override_days_factor) }
    else
      { period_type => calculate_new_period_range(existing_range, start_factor, end_factor) }
    end
  end

  def days_in_date_range(daterange)
    (daterange.last - daterange.first + (daterange.exclude_end? ? 0 : 1)).to_i
  end
end

class ChartManagerTimescaleManipulationMove < ChartManagerTimescaleManipulation
  def initialize(type, holidays, original_chart_config)
    super(type, holidays, original_chart_config)
  end

  def manipulate_timescale(timescale, factor, available_periods)
    raise EnergySparksUnexpectedStateException, "Expecting single entry hash, got #{timescale}" if timescale.length != 1
    period_type, period_number = timescale.first
    if period_number.is_a?(Integer)
      new_period_number = calculate_new_period_number(period_number, factor, available_periods)
      { period_type => new_period_number }
    elsif period_number.is_a?(Range)
      calculate_new_range(period_type, period_number, factor, factor)
    else
      raise EnergySparksUnexpectedStateException, "Unsupported period number #{period_number} type"
    end
  end
end

class ChartManagerTimescaleManipulationNonMoveTypes < ChartManagerTimescaleManipulation
  def chart_suitable_for_timescale_manipulation?
    return false unless super
    timescale, _value = timescale_type(@original_chart_config)
    !(@original_chart_config[:timescale].is_a?(Array) && @original_chart_config[:timescale].length > 1) &&
    !%i[frostday frostday_3 optimum_start diurnal].include?(timescale)
  end
end

class ChartManagerTimescaleManipulationExtend < ChartManagerTimescaleManipulationNonMoveTypes
  def initialize(type, holidays, original_chart_config)
    super(type, holidays, original_chart_config)
  end

  def manipulate_timescale(timescale, factor, available_periods)
    raise EnergySparksUnexpectedStateException, "Expecting single entry hash, got #{timescale}" if timescale.length != 1
    period_type, period_number = timescale.first
    if period_number.is_a?(Integer)
      new_period_number = calculate_new_period_number(period_number, factor, available_periods)
      new_range = factor > 0 ? Range.new(period_number, new_period_number) : Range.new(new_period_number, period_number)
      {period_type => new_range}
    elsif period_number.is_a?(Range)
      override_days_factor = date_range?(period_number) ? days_in_date_range(period_number) : nil
      calculate_new_range(period_type, period_number, factor > 0 ? 0 : factor, factor < 0 ? 0 : factor, override_days_factor)
    else
      raise EnergySparksUnexpectedStateException, "Unsupported period number #{period_number} type"
    end
  end
end

class ChartManagerTimescaleManipulationContract < ChartManagerTimescaleManipulationNonMoveTypes
  def initialize(type, holidays, original_chart_config)
    super(type, holidays, original_chart_config)
  end

  def manipulate_timescale(timescale, factor, available_periods)
    raise EnergySparksUnexpectedStateException, "Expecting single entry hash, got #{timescale}" if timescale.length != 1
    period_type, period_number = timescale.first
    if period_number.is_a?(Integer)
      # do nothing as can't contract single time range, should potentially raise error
      # PH 22Aug2019, see chart_suitable_for_timescale_manipulation test above
      {period_type => period_number}
    elsif period_number.is_a?(Range)
      raise EnergySparksNotEnoughDataException, 'Cant contract back beyond original chart size if date range (typically a drilldown)' if not_enough_periods(period_number)
      calculate_new_range(period_type, period_number, factor > 0 ? 0 : (-1 * factor), factor < 0 ? 0 : (-1 * factor), @original_chart_config[:cadence_days], true)
    else
      raise EnergySparksUnexpectedStateException, "Unsupported period number #{period_number} type"
    end
  end

  private def not_enough_periods(range)
    date_range?(range) && @original_chart_config.key?(:cadence_days) && days_in_date_range(range) == @original_chart_config[:cadence_days]
  end
end

# compare with nth period before or after
#   - however, if this is already a chart which includes comparisons
#   - its a little unclear what the best result might be
#   - for example compare [ {schoolweek: 0}, {schoolweek: -30}] with the previous period?
#   - do you want [ {schoolweek: -1..0}, {schoolweek: -30..-31}]  ?
#   - or  [ {schoolweek: 0}, {schoolweek: -30}, {schoolweek: -60}, {schoolweek: -90}]
#   - PH 22Aug2019 - decided to to say chart can't be compared
class ChartManagerTimescaleManipulationCompare < ChartManagerTimescaleManipulationNonMoveTypes
  def initialize(type, holidays, original_chart_config)
    super(type, holidays, original_chart_config)
  end

  def chart_suitable_for_timescale_manipulation?
    return false unless super
    !is_thermostatic_chart?(@original_chart_config)
  end

  def timescale_adjust(timescales, factor, available_periods)
    new_timescales = []
    timescale_comparison_to_extend = factor > 0 ? timescales.last : timescales.first
    additional_comparison = manipulate_timescale(timescale_comparison_to_extend, factor, available_periods)
    new_timescales = factor > 0 ? [timescales, additional_comparison] : [additional_comparison, timescales]
    new_timescales.flatten
  end

  def manipulate_timescale(timescale, factor, available_periods)
    raise EnergySparksUnexpectedStateException, "Expecting single entry hash, got #{timescale}" if timescale.length != 1
    period_type, period_number = timescale.first
    if period_number.is_a?(Integer)
      new_period_number = calculate_new_period_number(period_number, factor, available_periods)
      { period_type => new_period_number }
    elsif period_number.is_a?(Range)
      calculate_new_range(period_type, period_number, factor, factor)
    else
      raise EnergySparksUnexpectedStateException, "Unsupported period number #{period_number} type"
    end
  end
end
