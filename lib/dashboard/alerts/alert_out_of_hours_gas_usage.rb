#======================== Gas: Out of hours usage =============================
require_relative 'alert_out_of_hours_base_usage.rb'

class AlertOutOfHoursGasUsage < AlertOutOfHoursBaseUsage
  def initialize(school)
    super(school, 'gas', BenchmarkMetrics::PERCENT_GAS_OUT_OF_HOURS_BENCHMARK,
          BenchmarkMetrics::GAS_PRICE, :gasoutofhours, 'GasOutOfHours', :allheat)
  end
end