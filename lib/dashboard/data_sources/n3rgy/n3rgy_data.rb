module MeterReadingsFeeds
  class N3rgyData
    include Logging

    class BadParameters < StandardError; end

    KWH_PER_M3_GAS = 11.1 # this depends on the calorifc value of the gas and so is an approximate average

    # N3RGY_DATA_BASE_URL : 'https://api.data.n3rgy.com/' or 'https://sandboxapi.data.n3rgy.com/'

    def initialize(api_key: ENV['N3RGY_API_KEY'], base_url: ENV['N3RGY_DATA_BASE_URL'], debugging: nil, bad_electricity_standing_charge_units: ENV['N3RGY_BAD_UNITS'])
      @api_key = api_key
      @base_url = base_url
      @debugging = debugging
      @bad_electricity_standing_charge_units = bad_electricity_standing_charge_units
    end

    def readings(mpxn, fuel_type, start_date, end_date)
      raise BadParameters.new("Please specify start and end date") if start_date.nil? || end_date.nil?
      if fuel_type == :exported_solar_pv
        readings_by_date = production_data(mpxn, fuel_type, start_date, end_date)
      else
        readings_by_date = consumption_data(mpxn, fuel_type, start_date, end_date)
      end
      meter_readings = X48Formatter.convert_dt_to_v_to_date_to_v_x48(start_date, end_date, readings_by_date, true)
      { fuel_type =>
          {
            mpan_mprn:        mpxn,
            readings:         make_one_day_readings(meter_readings[:readings], mpxn),
            missing_readings: meter_readings[:missing_readings]
          }
      }
    end

    def tariffs(mpxn, fuel_type, start_date, end_date)
      raise BadParameters.new("Please specify start and end date") if start_date.nil? || end_date.nil?
      tariff_details = tariff_data(mpxn, fuel_type, start_date, end_date)
      charges_by_date = tariff_details[:standing_charges].to_h
      prices_by_date = tariff_details[:prices].to_h
      tariff_readings = X48Formatter.convert_dt_to_v_to_date_to_v_x48(start_date, end_date, prices_by_date)
      {
        kwh_tariffs:      tariff_readings[:readings],
        standing_charges: charges_by_date,
        missing_readings: tariff_readings[:missing_readings],
      }
    end

    def inventory(mpxn)
      details = api.read_inventory(mpxn: mpxn)
      # seems like requesting file too soon causes Access Denied response
      sleep(1.5)
      api.fetch(details['uri'])
    end

    def status(mpxn)
      api.status(mpxn)
      :available
    rescue MeterReadingsFeeds::N3rgyDataApi::NotFound
      :unknown
    rescue MeterReadingsFeeds::N3rgyDataApi::NotAllowed
      :consent_required
    end

    private

    def consumption_data(mpxn, fuel_type, start_date, end_date)
      readings = []
      (start_date..end_date).each_slice(90) do |date_range_max_90days|
        response = api.get_consumption_data(mpxn: mpxn,
                                            fuel_type: fuel_type.to_s,
                                            start_date: date_range_max_90days.first,
                                            end_date: date_range_max_90days.last)
        readings += unit_adjusted_readings(response['values'], response['unit'])
      end
      readings.to_h
    end

    def production_data(mpxn, fuel_type, start_date, end_date)
      readings = []
      (start_date..end_date).each_slice(90) do |date_range_max_90days|
        response = api.get_production_data(mpxn: mpxn,
                                            fuel_type: fuel_type.to_s,
                                            start_date: date_range_max_90days.first,
                                            end_date: date_range_max_90days.last)
        readings += unit_adjusted_readings(response['values'], response['unit'])
      end
      readings.to_h
    end

    def tariff_data(mpxn, fuel_type, start_date, end_date)
      standing_charges = []
      prices = []
      (start_date..end_date).each_slice(90) do |date_range_max_90days|
        response = api.get_tariff_data(mpxn: mpxn,
                                       fuel_type: fuel_type.to_s,
                                       start_date: date_range_max_90days.first,
                                       end_date: date_range_max_90days.last)
        response['values'].each do |tariff|
          standing_charges += unit_adjusted_standing_charges(tariff['standingCharges'], fuel_type)
          prices += unit_adjusted_prices(tariff['prices'])
        end
      end
      {
        standing_charges: standing_charges,
        prices:           prices
      }
    end

    def unit_adjusted_readings(raw_readings, units)
      adjust_kwh_units = to_kwh(units)
      raw_readings.map do |reading|
        [
          DateTime.parse(reading['timestamp']),
          reading['value'] * adjust_kwh_units
        ]
      end
    end

    def unit_adjusted_prices(raw_prices)
      raw_prices.map do |price|
        [
          DateTime.parse(price['timestamp']),
          convert_to_£(tariff_price(price))
        ]
      end
    end

    def unit_adjusted_standing_charges(raw_standing_charges, fuel_type)
      raw_standing_charges.map do |standing_charge|
        [
          DateTime.parse(standing_charge['startDate']),
          convert_to_£(standing_charge['value'], fuel_type)
        ]
      end
    end

    def to_kwh(units)
      units == 'm3' ? KWH_PER_M3_GAS : 1.0
    end

    def tariff_price(tariff)
      # may be multiple prices for peroid based on usage levels - ignore for the moment
      tariff['prices'] ? tariff['prices'][0]['value'] : tariff['value']
    end

    # quote from N3rgy support:
    # "in sandbox environment, electricity tariffs have the standing charges in £/day and the TOU prices in pence/kWh. Gas tariffs are in pence/day and pence/kWh.
    # However, in live environment, our system returns always pence/day and pence/kWh."
    def convert_to_£(value, fuel_type = nil)
      if (fuel_type == :electricity && @bad_electricity_standing_charge_units)
        value
      else
        value / 100.0
      end
    end

    def make_one_day_readings(meter_readings_by_date, mpan_mprn)
      meter_readings_by_date.map do |date, readings|
        [date, OneDayAMRReading.new(mpan_mprn, date, 'ORIG', nil, DateTime.now, readings)]
      end.to_h
    end

    def api
      @api ||= N3rgyDataApi.new(@api_key, @base_url, @debugging)
    end
  end
end
