require "http"
require "json"
require "base64"
require "openssl"

require "./utils"
require "./models"
require "./illust"
require "./user"
require "./bookmark"
require "./ugoira"

module Pixiv
  Log = ::Log.for "pixiv"
  VERSION = "0.1.0"

  # Values scrapped from the official app required for proper authorization
  CLIENT_ID = "MOBrBDS8blbauoSck0ZfDbtuzpyT"
  CLIENT_SECRET = "lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj"
  HASH_SECRET = "28c1fdd170a5204386cb1313c7077b34f83e4aaf4aa829ce78c231e05b0bae2c"

  # Send these headers to look like the official Pixiv app
  DEFAULT_HEADERS = HTTP::Headers{
    "app-os" => "ios",
    "app-os-version" => "14.6",
    "user-agent" => "PixivIOSApp/7.13.3 (iOS 14.6; iPhone13,2)",
    "Accept-Language" => "en",
  }

  class Client
    @client : HTTP::Client
    @refresh_token : String
    @access_token : String
    @expires_at : Time

    property user : User

    def initialize(@refresh_token)
      info = Client.refresh @refresh_token
      @access_token = info.access_token
      @refresh_token = info.refresh_token
      @expires_at = (Time.utc + Time::Span.new(seconds: info.expires_in))
      @user = info.user.to_user
      @client = HTTP::Client.new URI.parse("https://app-api.pixiv.net")
      raise "failed to get access token" if @access_token == ""
    end

    # Refresh access token
    def self.refresh(refresh_token : String) : RefreshInfo
      datetime = Time::Format::RFC_3339.format Time.utc
      datehash = Base64.encode(OpenSSL::MD5.hash(datetime + HASH_SECRET))[..-2]

      headers = DEFAULT_HEADERS.dup
      headers["x-client-time"] = datetime
      headers["x-client-hash"] = datehash

      io = IO::Memory.new
      HTTP::FormData.build(io) do |builder|
        headers["Content-Type"] = builder.content_type
        builder.field "get_secure_url", 1
        builder.field "client_id", CLIENT_ID
        builder.field "client_secret", CLIENT_SECRET
        builder.field "grant_type", "refresh_token"
        builder.field "refresh_token", refresh_token
      end
      io.rewind

      res = HTTP::Client.post "https://oauth.secure.pixiv.net/auth/token", body: io, headers: headers
      if [200, 301, 302].includes? res.status_code
        Log.debug { "Token refresh successfull" }
      else
        Log.error { "Failed to refresh access token! Status: #{res.status} (#{res.status_code})\n#{res.body}" }
        raise "token refresh failed"
      end

      RefreshInfo.from_json res.body
    end

    # Search for users
    def search_user(query : String, sort : Sort = Sort::None) : UserQuery
      params = sort == Sort::None ? {} of String => String : {"sort" => sort.to_s}
      res = self.get url, params, word: query
      response_error res, "user search request failed" unless res.success?
      UserQuery.from_json res.body
    end

    private def get_auth_headers
      headers = DEFAULT_HEADERS.dup
      headers["Authorization"] = "Bearer #{@access_token}"
      headers
    end

    private def get(path : String, dyn_data = {} of String => String | UInt64, **data) : HTTP::Client::Response
      self.refresh_token if @expires_at <= Time.utc

      data = data.to_h.merge dyn_data unless dyn_data.size == 0

      params = ""
      unless data.size == 0
        data.each do |key, value|
          params += params.size == 0 ? "?" : "&"
          value = URI.encode_path value.to_s unless value.is_a?(Number)
          params += "#{URI.encode_path key.to_s}=#{value}"
        end
      end

      @client.get path+params, headers: self.get_auth_headers
    end

    private def post(path : String, dyn_data = {} of String => String | UInt64, **data) : HTTP::Client::Response
      self.refresh_token if @expires_at <= Time.utc

      data = data.to_h.merge dyn_data unless dyn_data.size == 0

      headers = self.get_auth_headers

      io = IO::Memory.new
      HTTP::FormData.build(io) do |builder|
        headers["Content-Type"] = builder.content_type
        data.each do |key, value|
          builder.field key.to_s, value.to_s
        end
      end
      io.rewind

      @client.post path, body: io, headers: headers
    end

    private def response_error(response : HTTP::Client::Response, message : String)
      Log.error { "Request failed! Status: #{response.status} (#{response.status_code})" }
      body = response.body
      begin
        body = JSON.parse(body).to_pretty_json
      rescue
      end
      Log.debug { "Error body:\n#{body}" }
      raise message
    end

    private def refresh_token
      info = Client.refresh @refresh_token
      @access_token = info.access_token
      @refresh_token = info.refresh_token
      @expires_at = (Time.utc + Time::Span.new(seconds: info.expires_in))
    end

    private struct RefreshInfo
      include JSON::Serializable

      property access_token : String
      property refresh_token : String
      property expires_in : UInt32
      property user : OAuthUser
    end

    struct OAuthUser
      include JSON::Serializable

      property id : String
      property name : String
      property account : String
      property profile_image_urls : Hash(String, String)

      def to_user : User
        User.new self.id.to_u64, self.name, self.account, Avatar.new(self.profile_image_urls.last_value? || "")
      end
    end
  end
end
