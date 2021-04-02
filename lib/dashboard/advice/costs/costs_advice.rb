class CostAdviceBase < AdviceOldToNewConversion
  include MeterlessMixin
  def create_class(old_advice_class)
    return nil if old_advice_class.nil?
    args = old_advice_class.instance_method(:initialize).arity
    case args
    when 1
      old_advice_class.new(@school)
    when 4, -5
      old_advice_class.new(@school, nil, nil, nil)
    else
      raise EnergySparksUnexpectedStateException, "Unexpected number of arguments #{args}"
    end
  end

  def erb_bind(text)
    ERB.new(text).result(binding)
  end
end

class CostsIntroductionAdvice < CostAdviceBase
  def initialize(school)
    super(school)
    @summary = "Your School\'s #{fuel_type.to_s.capitalize} Costs" 
    @content_data = [
      { type: :text, advice_class: advice_class, data: "<h2>#{@summary}</h2>"},
      { type: :text, advice_class: advice_class, data: availability_of_meter_tariffs_text },
      { type: :text, advice_class: advice_class, data: "<p><b>Comparison of last 2 years #{fuel_type.to_s.capitalize} costs</b></p>" },
      { type: :chart_and_text, data: chart_2_year_comparison },
      { type: :chart_and_text, data: chart_1_year_breakdown, components: [true, false, false] },
      { type: :text, advice_class: advice_class, data: "<p><b>Your last year\'s #{fuel_type.capitalize} bill components</b></p>" },
      { type: :text, advice_class: advice_class, data: "<p>Last year's bill components were as follows: </p>" },
      { type: :chart_and_text, data: chart_1_year_breakdown, components: [false, true, true] }
    ]
  end

  def advice_class
    AdviceElectricityCosts
  end

  def availability_of_meter_tariffs_text
    text = if rating == 10.0
      %q(
        <p>
          The information below provides a good estimate of your annual
          <%=  fuel_type %> costs based on meter tariff information which
          has been provided to Energy Sparks.
        </p>
      )
    elsif rating == 0.0
      %q(
        <p>
          The information below is approximate as we don't have your meter tariffs
          so are using average tariffs for your area. If you would like this web page
          to provide accurate information please provide us with your
          meter tariffs <%= email_us_html(@email_subject, 'via email') %> and we
          can help setup the tariffs so you get accurate information on this page.
        </p>
      )
    else
      %q(
        <p>
          The information below is approximate as we don't have all your meter tariff information.
          We are using a mix of your actual tariffs and some average tariffs for your
          area. If you would like this web page
          to provide accurate information please <%= email_us_html('Meter tariff information for my school', 'get in contact') %> 
          and we can help setup the remaining tariffs.
        </p>
      )
    end
  end
end


class CostsHowEnergySparksCalculatesThem < CostAdviceBase
  def initialize(school)
    super(school)
    @summary = 'How Energy Sparks calculates energy costs'
    @content_data = [
      { type: :text, advice_class: self.class, data: "<p><b>How Energy Sparks calculates costs</b></p>" },
      { type: :text, advice_class: DashboardEnergyAdvice::FinancialAdviceBase, data: DashboardEnergyAdvice::FinancialAdviceBase::INTRO_TO_SCHOOL_FINANCES_1 },
    ]
  end
end

class MeterTariffInfo < CostAdviceBase
  def initialize(school)
    super(school)
    @summary = "Your meter #{fuel_type.to_s.capitalize} Tariffs"
    tariff_table = FormatMeterTariffs.new(@school).tariff_tables_html(meters)
    @content_data = [
      { type: :text, advice_class: self.class, data: tariff_table },
    ]
  end
  def rating
    @rating ||= 100.0 * MeterTariffs.accounting_tariff_availability_coverage(aggregate_meter.amr_data.start_date, aggregate_meter.amr_data.end_date, underlying_meters)
  end
end

class ElectricityTariffs < MeterTariffInfo
  def meters; @school.electricity_meters end
  def fuel_type; :electricity end
end

class AdviceFuelTypeBase < AdviceStructuredOldToNewConversion
  def initialize(school)
    super(school)
    @summary = fuel_type.to_s.capitalize + ' Costs'
  end
  def relevance
    return :never_relevant if aggregate_meter.nil?
    tariffs = MeterTariffs.accounting_tariffs_available_for_period?(aggregate_meter.amr_data.start_date, aggregate_meter.amr_data.end_date, underlying_meters)
    tariffs ? :relevant : :never_relevant
  end
  # overwrite structured content old to new converter
  # so can do per meter analysis
  def structured_content(user_type: nil)
    content_information = []
    component_pages.each do |component_page_class|
      component_page = component_page_class.new(@school)
      content_information.push(
        {
          title:    component_page.summary,
          content:  component_page.content
        }
      ) if component_page.relevance == :relevant
    end
    content_information += meter_costs
    content_information
  end
  def advice_class; self.class end
  def has_structured_content?; true end

  def meter_costs
    real_meters.map do |meter|
      MeterCost.new(@school,meter).content
    end
  end

  def real_meters
    @school.real_meters.select { |m| m.fuel_type == fuel_type }
  end
end

class ElectricityCostsIntroductionAdvice < CostsIntroductionAdvice
  def fuel_type; :electricity end
  def chart_2_year_comparison; :electricity_cost_comparison_last_2_years_accounting end
  def chart_1_year_breakdown; :electricity_cost_1_year_accounting_breakdown end
end

class AdviceElectricityCosts < AdviceFuelTypeBase
  def fuel_type; :electricity end

  def component_pages
    [
      ElectricityCostsIntroductionAdvice,
      CostsHowEnergySparksCalculatesThem,
      ElectricityTariffs
    ]
  end

  def aggregate_meter
    @school.aggregated_electricity_meters
  end

  def underlying_meters; @school.electricity_meters end
end

class GasTariffs < MeterTariffInfo
  def meters; @school.heat_meters end
  def fuel_type; :gas end
end

class GasCostsIntroductionAdvice < CostsIntroductionAdvice
  def fuel_type; :gas end
  def chart_2_year_comparison; :gas_cost_comparison_last_2_years_accounting end
  def chart_1_year_breakdown; :gas_cost_1_year_accounting_breakdown end
end

class AdviceGasCosts < AdviceFuelTypeBase
  def fuel_type; :gas end

  def component_pages
    [
      GasCostsIntroductionAdvice,
      CostsHowEnergySparksCalculatesThem,
      GasTariffs
    ]
  end

  def aggregate_meter
    @school.aggregated_heat_meters
  end

  def underlying_meters; @school.heat_meters end
end