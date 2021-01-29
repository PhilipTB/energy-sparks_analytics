require_relative '../../../../lib/dashboard/data_sources/meteostat'
require_relative '../../../../lib/dashboard/data_sources/meteostat_api'

describe MeteoStat do

  let(:latitude)    { 123 }
  let(:longitude)   { 456 }
  let(:start_date)  { Date.parse('20210127') }
  let(:end_date)    { Date.parse('20210128') }
  let(:json_file)   { 'spec/fixtures/meteostatapi-27jan2021.json' }
  let(:json)        { JSON.parse(File.read(json_file)) }

  let(:expected_historic_temperatures) do
    {
      :temperatures=>
        {
          Date.parse('Wed, 27 Jan 2021')=>[4.9, 4.95, 5.0, 5.1, 5.2, 5.25, 5.3, 5.5, 5.7, 5.75, 5.8, 5.85, 5.9, 5.9, 5.9, 5.95, 6.0, 6.2, 6.4, 6.6, 6.8, 7.15, 7.5, 7.8, 8.1, 8.4, 8.7, 8.9, 9.1, 8.9, 8.7, 8.35, 8.0, 7.5, 7.0, 6.85, 6.7, 6.35, 6.0, 5.9, 5.8, 6.0, 6.2, 6.1, 6.0, 6.05, 6.1, 6.2],
          Date.parse('Thu, 28 Jan 2021')=>[6.3, 6.3, 6.3, 6.3, 6.3, 6.3, 6.3, 6.2, 6.1, 6.15, 6.2, 6.05, 5.9, 5.75, 5.6, 5.55, 5.5, 5.6, 5.7, 5.9, 6.1, 6.4, 6.7, 7.05, 7.4, 7.75, 8.1, 8.45, 8.8, 9.0, 9.2, 9.0, 8.8, 8.45, 8.1, 8.05, 8.0, 8.1, 8.2, 8.2, 8.2, 8.2, 8.2, 8.3, 8.4, 8.45, 8.5, 8.5]
        },
      :missing=>[]
    }
  end

  before do
    expect(MeteoStatApi).to receive(:get).and_return(json)
  end

  describe 'historic_temperatures' do
    it 'returns expected temperatures' do
      expect(MeteoStat.new.historic_temperatures(latitude, longitude, start_date, end_date)).to eq(expected_historic_temperatures)
    end
  end
end
