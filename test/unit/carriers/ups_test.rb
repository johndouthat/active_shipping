require File.dirname(__FILE__) + '/../../test_helper'

class UPSTest < Test::Unit::TestCase
  include ActiveMerchant::Shipping
  
  def setup
    @packages               = fixtures(:packages)
    @locations              = fixtures(:locations)
    @carrier                = UPS.new(
                                :key => 'key',
                                :login => 'login',
                                :password => 'password'
                              )
    @tracking_response = xml_fixture('ups/shipment_from_tiger_direct')
    @tnt_response = xml_fixture('ups/example_tnt_response')
  end
  
  def test_initialize_options_requirements
    assert_raises ArgumentError do UPS.new end
    assert_raises ArgumentError do UPS.new(:login => 'blah', :password => 'bloo') end
    assert_raises ArgumentError do UPS.new(:login => 'blah', :key => 'kee') end
    assert_raises ArgumentError do UPS.new(:password => 'bloo', :key => 'kee') end
    assert_nothing_raised { UPS.new(:login => 'blah', :password => 'bloo', :key => 'kee')}
  end
  
  def test_find_tracking_info_should_return_a_tracking_response
    UPS.any_instance.expects(:commit).returns(@tracking_response)
    assert_equal 'ActiveMerchant::Shipping::TrackingResponse', @carrier.find_tracking_info('1Z5FX0076803466397').class.name
  end
  
  def test_find_tracking_info_should_parse_response_into_correct_number_of_shipment_events
    UPS.any_instance.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('1Z5FX0076803466397')
    assert_equal 8, response.shipment_events.size
  end
  
  def test_find_tracking_info_should_return_shipment_events_in_ascending_chronological_order
    UPS.any_instance.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('1Z5FX0076803466397')
    assert_equal response.shipment_events.map(&:time).sort, response.shipment_events.map(&:time)
  end
  
  def test_find_tracking_info_should_have_correct_names_for_shipment_events
    UPS.any_instance.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('1Z5FX0076803466397')
    assert_equal [ "BILLING INFORMATION RECEIVED",
                   "IMPORT SCAN",
                   "LOCATION SCAN",
                   "LOCATION SCAN",
                   "DEPARTURE SCAN",
                   "ARRIVAL SCAN",
                   "OUT FOR DELIVERY",
                   "DELIVERED" ], response.shipment_events.map(&:name)
  end
  
  def test_add_origin_and_destination_data_to_shipment_events_where_appropriate
    UPS.any_instance.expects(:commit).returns(@tracking_response)
    response = @carrier.find_tracking_info('1Z5FX0076803466397')
    assert_equal '175 AMBASSADOR', response.shipment_events.first.location.address1
    assert_equal 'K1N5X8', response.shipment_events.last.location.postal_code
  end
  
  def test_response_parsing
    mock_response = xml_fixture('ups/test_real_home_as_residential_destination_response')
    UPS.any_instance.expects(:commit).returns(mock_response)
    response = @carrier.find_rates( @locations[:beverly_hills],
                                    @locations[:real_home_as_residential],
                                    @packages.values_at(:chocolate_stuff))
    assert_equal [ "UPS Ground",
                   "UPS Three-Day Select",
                   "UPS Second Day Air",
                   "UPS Next Day Air Saver",
                   "UPS Next Day Air Early A.M.",
                   "UPS Next Day Air"], response.rates.map(&:service_name)
    assert_equal [992, 2191, 3007, 5509, 9401, 6124], response.rates.map(&:price)
  end
  
  def test_xml_logging_to_file
    mock_response = xml_fixture('ups/test_real_home_as_residential_destination_response')
    UPS.any_instance.expects(:commit).times(2).returns(mock_response)
    RateResponse.any_instance.expects(:log_xml).with({:name => 'test', :path => '/tmp/logs'}).times(1).returns(true)
    response = @carrier.find_rates( @locations[:beverly_hills],
                                    @locations[:real_home_as_residential],
                                    @packages.values_at(:chocolate_stuff),
                                    :log_xml => {:name => 'test', :path => '/tmp/logs'})
    response = @carrier.find_rates( @locations[:beverly_hills],
                                    @locations[:real_home_as_residential],
                                    @packages.values_at(:chocolate_stuff))
  end
  
  def test_tnt_response_parsing
    UPS.any_instance.expects(:commit).returns(@tnt_response)
    response = @carrier.find_time_in_transit(@locations[:prague_example], @locations[:roswell_example], Date.today, 2.0, nil, 500, false, 5)
    
    assert_equal response.disclaimer, "All services are guaranteed if shipment is paid for in full by a payee in the United States. Services listed as guaranteed are backed by a money-back guarantee for transportation charges only. See Terms and Conditions in the Service Guide for details. Certain commodities and high value shipments may require additional transit time for customs clearance."
    
    expected = [
      {:code => '21', :delivery_at => Time.parse('2007-11-24 09:30:00')},
      {:code => '01', :delivery_at => Time.parse('2007-11-24 12:00:00')}
      # TODO? ....
    ]
    
    assert_equal response.services.size, 6
    assert_equal response.origin_candidates.size, 0
    assert_equal response.destination_candidates.size, 0
    
    0.upto(expected.size-1) do |i|
      service = response.services[i]
      assert_equal service.service_code, expected[i][:code]
      assert_equal service.delivery_at, expected[i][:delivery_at]
      assert_equal service.guaranteed?, true
    end
    
  end
end