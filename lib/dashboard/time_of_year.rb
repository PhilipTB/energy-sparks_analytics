# time of year - so only month and day of month
class TimeOfYear
  include Comparable

  attr_reader :month, :day_of_month, :relative_time

  def initialize(month, day_of_month)
    @relative_time = Time.new(1970, month, day_of_month, 0, 0, 0)
    @month = month
    @day_of_month = day_of_month
  end

  def self.to_toy(date)
    TimeOfYear.new(date.month, date.day)
  end

  # within period inclusive, dealing with end of yer
  def self.within_period(toy, start_toy_period, end_toy_period)
    if start_toy_period < end_toy_period # within same year
      toy >= start_toy_period && toy <= end_toy_period
    else
      toy >= start_toy_period || toy <= end_toy_period
    end
  end

  def day
    relative_time.day
  end

  def to_s
    @relative_time.strftime('%d %b')
  end

  def <=>(other)
    other.class == self.class && [month, day] <=> [other.month, other.day]
  end
end
