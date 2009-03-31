module ActiveMerchant
  module Shipping
    class UPS < Carrier
      self.retry_safe = true
      
      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"
      
      TEST_URL = 'https://wwwcie.ups.com'
      LIVE_URL = 'https://www.ups.com'
      
      RESOURCES = {
        :rates => '/ups.app/xml/Rate',
        :track => '/ups.app/xml/Track',
        :time_in_transit => '/ups.app/xml/TimeInTransit',
        :address_validation => '/ups.app/xml/AV',
      }
      
      def requirements
        [:key, :login, :password]
      end
      
      protected
      def build_access_request
        xml_request = XmlNode.new('AccessRequest') do |access_request|
          access_request << XmlNode.new('AccessLicenseNumber', @options[:key])
          access_request << XmlNode.new('UserId', @options[:login])
          access_request << XmlNode.new('Password', @options[:password])
        end
        xml_request.to_xml
      end
      
      def response_success?(xml)
        xml.get_text('/*/Response/ResponseStatusCode').to_s == '1'
      end
      
      def response_message(xml)
        xml.get_text('/*/Response/ResponseStatusDescription | /*/Response/Error/ErrorDescription').to_s
      end
      
      def commit(action, request, test = false)
        ssl_post("#{test ? TEST_URL : LIVE_URL}/#{RESOURCES[action]}", request)
      end
      
      def xml(*args)
        XmlNode.new(*args) { |x| yield(x) if block_given? }
      end
      
    end
  end
end

require 'active_shipping/shipping/carriers/ups/rate_and_service_selection'
require 'active_shipping/shipping/carriers/ups/tracking'
require 'active_shipping/shipping/carriers/ups/time_in_transit'
require 'active_shipping/shipping/carriers/ups/address_validation'