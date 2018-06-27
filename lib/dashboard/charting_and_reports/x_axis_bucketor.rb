# implement X Axis bucketing as a series of derived classes
#  - probably more tranparent and debugable than lamda's or procs, and mixins are too static

class XBucketBase
  attr_reader :x_axis, :x_axis_bucket_date_ranges
  def initialize(type, periods)
    @type = type
    @periods = periods
    @x_axis = []
    @x_axis_bucket_date_ranges = []
  end

  def index(date, halfhour_index)
    @x_axis.index(key(date, halfhour_index))
  end

  def key(_date, _halfhour_index)
    raise 'key: Not implemented - incorrect call to base class'
  end

  def create_x_axis
    raise 'key: Not implemented - incorrect call to base class'
  end

  def data_start_date
    @periods[0].start_date
  end

  def data_end_date
    @periods[0].end_date
  end

  def compact_date_range_description
    format = '%a%d%b%y'
    if data_start_date != data_end_date
      data_start_date.strftime(format) + '-' + data_end_date.strftime(format)
    else
      data_start_date.strftime(format)
    end
  end

  # Factory Method for creating the right type of x bucketing object
  def self.create_bucketor(type, periods)
    case type
    when :month
      XBucketMonth.new(type, periods)
    when :week
      XBucketWeek.new(type, periods)
    when :day
      XBucketDay.new(type, periods)
    when :dayofweek
      XBucketDayOfWeek.new(type, periods)
    when :academicyear
      XBucketAcademicYear.new(type, periods)
    when :year
      XBucketYearToDate.new(type, periods)
    when :intraday
      XBucketIntraday.new(type, periods)
    when :datetime
      XBucketDateTime.new(type, periods)
    when :nodatebuckets
      XBucketSingle.new(type, periods)
    else
      raise "Unknown x bucket type " + type.to_s
    end
  end
end

class XBucketMonth < XBucketBase
  def initialize(type, periods)
    super(type, periods)
  end

  def key(date, _halfhour_index)
    date.strftime("%b %Y")
  end

  def create_x_axis
    first_day_of_month = data_start_date # .beginning_of_month
    while first_day_of_month <= data_end_date
      @x_axis.push(first_day_of_month.strftime("%b %Y"))
      last_day_of_month = first_day_of_month.beginning_of_month.next_month - 1 # can't use end_of_month as there is a active_support error: undefined method `days_in_month'
      @x_axis_bucket_date_ranges.push([first_day_of_month, last_day_of_month])
      first_day_of_month = first_day_of_month.next_month.beginning_of_month
    end
    @x_axis_bucket_date_ranges.last[1] = data_end_date if @x_axis_bucket_date_ranges.last[1] > data_end_date
  end
end

class XBucketAcademicYear < XBucketBase
  def initialize(type, periods)
    super(type, periods)
  end

  def key(date, _halfhour_index)
    period = SchoolDatePeriod.find_period_for_date(date, @periods)
    description(period)
  end

  def description(period)
    'Academic Year ' + period.start_date.strftime("%y") + '/' + period.end_date.strftime("%y")
  end

  def create_x_axis
    @periods.each do |period|
      @x_axis.push(description(period))
      @x_axis_bucket_date_ranges.push([period.start_date, period.end_date])
    end
  end

  def data_start_date
    @periods.last.start_date # year arrays in reverse order so most recent is 1st in presentation
  end

  def data_end_date
    @periods.first.end_date
  end
end

class XBucketYearToDate < XBucketAcademicYear
  def initialize(type, periods)
    super(type, periods)
  end

  def description(period)
    period.start_date.strftime("%d %b %Y") + ' to ' + period.end_date.strftime("%d %b %Y")
  end
end


class XBucketWeek < XBucketBase
  def initialize(type, periods)
    super(type, periods)
    first_day_of_period = data_start_date
    @first_sunday = first_day_of_period - first_day_of_period.wday # move to Sunday boundaries so holiday/weekend bucketing looks ok
    @key_string = "%d %b %Y"
  end

  def key(date, _halfhour_index)
    first_sunday_of_bucket = @first_sunday + 7 * ((date - @first_sunday) / 7).floor.to_i
    first_sunday_of_bucket.strftime(@key_string)
  end

  # overwritten as provide report speed up from 0.52s to 0.44s
  def index(date, _halfhour_index)
    ((date - @first_sunday) / 7).floor.to_i
  end

  def create_x_axis
    (@first_sunday..data_end_date).step(7) do |date|
      if date + 6 <= data_end_date # make sure it use the final week if partial
        @x_axis_bucket_date_ranges.push([date, date + 6])
        @x_axis.push(date.strftime(@key_string))
      end
    end
  end
end

class XBucketIntraday < XBucketBase
  def initialize(type, periods)
    super(type, periods)
  end

  def key(_date, halfhour_index)
    hour = (halfhour_index / 2).to_s
    minutes = (halfhour_index / 2).floor.odd? ? '30' : '00'
    hour + ':' + minutes # hH:MM
  end

  def index(_date, halfhour_index)
    halfhour_index
  end

  def create_x_axis
    (0..47).each do |halfhour_index|
      @x_axis.push(key(nil, halfhour_index))
      # this is a slight fudge as the 1/2 hour buckets technically have no date
      # range, but this allows the upstream kWh to kW converted to know the date
      # range in order to convert from kWh to kW generically without having to
      # look up the date ranges seperately
      @x_axis_bucket_date_ranges.push([data_start_date, data_end_date])
    end
  end
end

class XBucketDateTime < XBucketBase
  DTKEYFORMAT = '%a %d-%b-%Y %H:%M'
  def initialize(type, periods)
    super(type, periods)
  end

  def key(date, halfhour_index)
    datetime = DateTimeHelper.datetime(date, halfhour_index)
    datetime.strftime(DTKEYFORMAT)
  end

  def index(date, halfhour_index)
    ((date - data_start_date) * 48) + halfhour_index
  end

  def create_x_axis
    (data_start_date..data_end_date).each do |date|
      (0..47).each do |halfhour_index|
        dt_start = DateTimeHelper.datetime(date, halfhour_index)
        @x_axis_bucket_date_ranges.push([dt_start, dt_start])
        @x_axis.push(dt_start.strftime(DTKEYFORMAT))
      end
    end
  end
end

class XBucketDay < XBucketBase
  def initialize(type, periods)
    super(type, periods)
  end

  def key(date, _halfhour_index)
    date
  end

  def create_x_axis
    (data_start_date..data_end_date).each do |date|
      @x_axis_bucket_date_ranges.push([date, date])
      @x_axis.push(date)
    end
  end

  # overwritten as provide report speed up from 6.5s to 0.55s - base class key lookup expensive
  def index(date, _halfhour_index)
    date - data_start_date
  end
end

class XBucketDayOfWeek < XBucketBase
  def initialize(type, periods)
    super(type, periods)
  end

  def key(date, _halfhour_index)
    Date::DAYNAMES[date.wday]
  end

  def create_x_axis
    @x_axis = Date::DAYNAMES

    # this bit is a slight fudge as the x_axis doesn't have date buckets, only days of week
    (data_start_date..data_end_date).each do |date|
      @x_axis_bucket_date_ranges.push([date, date])
    end
  end
end

# special case for pie charts where there is no dated x-axis
class XBucketSingle < XBucketBase
  def initialize(type, periods)
    super(type, periods)
  end

  def key(_date, _halfhour_index)
    'No Dates'
  end

  def create_x_axis
    @x_axis_bucket_date_ranges.push([data_start_date, data_end_date])
    @x_axis.push('No Dates')
  end

  def index(_date, _halfhour_index)
    0
  end
end
