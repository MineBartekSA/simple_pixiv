module Pixiv
  class Client
    # Get User bookmarks
    def user_bookmarks(user_id : UInt64, next_id : UInt64? = nil, restrict : Restrict = Restrict::Public) : BookmarkPage
      params = next_id.nil? ? {} of String => UInt64 : {"max_bookmark_id" => next_id}
      res = self.get "/v1/user/bookmarks/illust", params, restrict: restrict, user_id: user_id
      response_error res, "user bookmark request failed" unless res.success?
      BookmarkPage.from_json res.body
    end

    # Get Bookmark details
    def illust_bookmark_detail(illust_id : UInt64) : Bookmark
      res = self.get "/v2/illust/bookmark/detail", illust_id: illust_id
      response_error res, "bookmark request failed" unless res.success?
      # TODO: See if the model changes when you actually have the illustration bookmarked
      BookmarkBox.from_json(res.body).bookmark_detail
    end

    # Add Bookmark
    def illust_bookmark_add(illust_id : UInt64, restrict : Restrict = Restrict::Public)
      # TODO: Add tags
      res = self.post "/v2/illust/bookmark/add", illust_id: illust_id, restrict: restrict
      response_error res, "bookmark add request failed" unless res.success?
    end

    # Remove Bookmark
    def illust_bookmark_remove(illust_id : UInt64)
      res = self.post "/v1/illust/bookmark/delete", illust_id: illust_id
      response_error res, "bookmark remove request failed" unless res.success?
    end

    # Internal structures

    private struct BookmarkBox
      include JSON::Serializable

      property bookmark_detail : Bookmark
    end
  end

  # Public structures

  struct BookmarkPage
    include JSON::Serializable

    property illusts : Array(Illustration)
    @[JSON::Field(converter: Pixiv::URIConverter)]
    property next_url : URI # TODO: See if this is present if no more bookmarks are available

    def next_id : UInt64
      self.next_url.query_params["max_bookmark_id"].to_u64
    end
  end

  struct Bookmark
    include JSON::Serializable

    property is_bookmarked : Bool
    property tags : Array(Tag) # TODO: Eather add is_registerd to the Tag model or make a BookmarkTag model
    @[JSON::Field(converter: Pixiv::RestrictConverter)]
    property restrict : Restrict
  end
end
