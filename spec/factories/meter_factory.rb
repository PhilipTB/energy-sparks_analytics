FactoryBot.define do
  factory :meter, class: "Dashboard::Meter" do
    transient do
      meter_collection        { nil }
      amr_data                { build(:amr_data) }
      type                    { :gas }
      sequence(:identifier)   { |n| n }
      sequence(:name)         { |n| "Meter #{n}" }
      floor_area              { 0 }
      number_of_pupils        { 1 }
      solar_pv_installation   { nil }
      storage_heater_config   { nil }
      external_meter_id       { nil }
      meter_attributes        { {} }
    end

    initialize_with{ new(meter_collection: meter_collection,
      amr_data: amr_data, type: type, identifier: identifier,
      name: name, floor_area: floor_area, number_of_pupils: number_of_pupils,
      solar_pv_installation: solar_pv_installation,
      storage_heater_config: storage_heater_config,
      external_meter_id: external_meter_id,
      meter_attributes: meter_attributes) }
  end
end
