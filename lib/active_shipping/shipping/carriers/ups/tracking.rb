module ActiveMerchant
  module Shipping
    class UPS
      
      def find_tracking_info(tracking_number, options={})
        options = @options.update(options)
        access_request = build_access_request
        tracking_request = build_tracking_request(tracking_number, options)
        response = commit(:track, save_request(access_request + tracking_request), (options[:test] || false))
        parse_tracking_response(response, options)
      end
      
      protected
      
      def build_tracking_request(tracking_number, options={})
        xml_request = XmlNode.new('TrackRequest') do |root_node|
          root_node << XmlNode.new('Request') do |request|
            request << XmlNode.new('RequestAction', 'Track')
            request << XmlNode.new('RequestOption', '1')
          end
          root_node << XmlNode.new('TrackingNumber', tracking_number.to_s)
        end
        xml_request.to_xml
      end
      
      def parse_tracking_response(response, options={})
        xml_hash = ActiveMerchant.parse_xml(response)['TrackResponse']
        success = response_hash_success?(xml_hash)
        message = response_hash_message(xml_hash)
        
        
        if success
          tracking_number, origin, destination = nil
          shipment_events = []
          
          first_shipment = first_or_only(xml_hash['Shipment'])
          first_package = first_or_only(first_shipment['Package'])
          tracking_number = first_shipment['ShipmentIdentificationNumber'] || first_package['TrackingNumber']
          origin, destination = %w{Shipper ShipTo}.map do |location|
            location_hash = first_shipment[location]
            if location_hash && (address_hash = location_hash['Address'])
              Location.new(
                :country =>     address_hash['CountryCode'],
                :postal_code => address_hash['PostalCode'],
                :province =>    address_hash['StateProvinceCode'],
                :city =>        address_hash['City'],
                :address1 =>    address_hash['AddressLine1'],
                :address2 =>    address_hash['AddressLine2'],
                :address3 =>    address_hash['AddressLine3']
              )
            else
              nil
            end
          end
          
          activities = force_array(first_package['Activity'])
          unless activities.empty?
            shipment_events = activities.map do |activity|
              address = activity['ActivityLocation']['Address']
              location = Location.new(
                :address1 => address['AddressLine1'],
                :address2 => address['AddressLine2'],
                :address3 => address['AddressLine3'],
                :city => address['City'],
                :state => address['StateProvinceCode'],
                :postal_code => address['PostalCode'],
                :country => address['CountryCode'])
              status = activity['Status']
              status_type = status['StatusType'] if status
              description = status_type['Description'] if status_type
            
              # for now, just assume UTC, even though it probably isn't
              zoneless_time = if activity['Time'] and activity['Date']
                hour, minute, second = activity['Time'].scan(/\d{2}/)
                year, month, day = activity['Date'][0..3], activity['Date'][4..5], activity['Date'][6..7]
                Time.utc(year , month, day, hour, minute, second)
              end
              ShipmentEvent.new(description, zoneless_time, location)
            end
            
            shipment_events = shipment_events.sort_by(&:time)
            
            if origin
              first_event = shipment_events[0]
              same_country = origin.country_code(:alpha2) == first_event.location.country_code(:alpha2)
              same_or_blank_city = first_event.location.city.blank? or first_event.location.city == origin.city
              origin_event = ShipmentEvent.new(first_event.name, first_event.time, origin)
              if same_country and same_or_blank_city
                shipment_events[0] = origin_event
              else
                shipment_events.unshift(origin_event)
              end
            end
            if shipment_events.last.name.downcase == 'delivered'
              shipment_events[-1] = ShipmentEvent.new(shipment_events.last.name, shipment_events.last.time, destination)
            end
          end
        end
        
        TrackingResponse.new(success, message, xml_hash,
          :xml => response,
          :request => last_request,
          :shipment_events => shipment_events,
          :origin => origin,
          :destination => destination,
          :tracking_number => tracking_number)
      end
      
      def first_or_only(xml_hash)
        xml_hash.is_a?(Array) ? xml_hash.first : xml_hash
      end
      
      def force_array(obj)
        obj.is_a?(Array) ? obj : [obj]
      end
      
    end
  end
end