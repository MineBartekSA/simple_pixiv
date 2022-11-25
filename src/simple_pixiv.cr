require "http"
require "json"
require "base64"
require "openssl"

require "./utils"
require "./models"

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

    def initialize(@refresh_token)
      @client = HTTP::Client.new URI.parse("https://app-api.pixiv.net")
      @access_token = ""
      @expires_at = Time.unix 0
      self.refresh
      raise "failed to get access token" if @access_token == ""
    end

    # Refresh token
    def refresh : RefreshInfo
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
        builder.field "refresh_token", @refresh_token
      end
      io.rewind

      res = HTTP::Client.post "https://oauth.secure.pixiv.net/auth/token", body: io, headers: headers
      if [200, 301, 302].includes? res.status_code
        Log.debug { "Token refresh succesfull" }
      else
        Log.error { "Failed to refresh access token!\n#{res.body}" }
        raise "token refresh failed"
      end

      info = RefreshInfo.from_json res.body
      @access_token = info.access_token
      @refresh_token = info.refresh_token
      @expires_at = (Time.utc + Time::Span.new(seconds: info.expires_in))
      info
    end

    # Get Illustration details
    def illust_detail(illust_id : UInt64) : Illustration
      res = @client.get "/v1/illust/detail?illust_id=#{illust_id}", headers: self.get_auth_header
      unless res.success?
        Log.error { "Status: #{res.status} (#{res.status_code})" }
        Log.error { res.body }
        raise "illust request failed"
      end
      IllustBox.from_json(res.body).illust
    end

    # Get User details
    def user_detail(user_id : UInt64) : User # TODO: Make UserDetail model
      res = @client.get "/v1/user/detail?user_id=#{user_id}", headers: self.get_auth_header
      unless res.success?
        Log.error { "Status: #{res.status} (#{res.status_code})" }
        Log.error { res.body }
        raise "user request failed"
      end
      UserBox.from_json(res.body).user
    end

    # Get User bookmarks
    def user_bookmarks(user_id : UInt64, next_id : UInt64? = nil) : BookmarkPage
      url = "/v1/user/bookmarks/illust?restrict=public&user_id=#{user_id}"
      url += "&max_bookmark_id=#{next_id}" unless next_id.nil?
      res = @client.get url, headers: self.get_auth_header
      unless res.success?
        Log.error { "Status: #{res.status} (#{res.status_code})" }
        Log.error { res.body }
        raise "user bookmark request failed"
      end
      BookmarkPage.from_json res.body
    end

    def illust_series(series_id : UInt64) : IllustrationSeries
      res = @client.get "/v1/illust/series?illust_series_id=#{series_id}", headers: self.get_auth_header
      unless res.success?
        Log.error { "Status: #{res.status} (#{res.status_code})" }
        Log.error { res.body }
        raise "illust series request failed"
      end
      IllustrationSeries.from_json res.body
    end

    # Search for users
    def search_user(query : String, sort : Sort = Sort::None) : UserSearch
      url = "/v1/search/user?word=#{URI.encode_path query}"
      url += "&sort=#{URI.encode_path sort.to_s}" if sort != ""
      res = @client.get url, headers: self.get_auth_header
      unless res.success?
        Log.error { "Status: #{res.status} (#{res.status_code})" }
        Log.error { res.body }
        raise "search request failed"
      end
      UserSearch.from_json res.body
    end

    private def get_auth_header
      self.refresh if @expires_at <= Time.utc
      headers = DEFAULT_HEADERS.dup
      headers["Authorization"] = "Bearer #{@access_token}"
      headers
    end
  end

  private struct RefreshInfo
    include JSON::Serializable

    property access_token : String
    property refresh_token : String
    property expires_in : UInt32
  end

  private struct IllustBox
    include JSON::Serializable

    property illust : Illustration
  end

  private struct UserBox
    include JSON::Serializable

    property user : User
  end
end
