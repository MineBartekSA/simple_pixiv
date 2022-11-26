module Pixiv
  class Client
    # Get User details
    def user_detail(user_id : UInt64) : User # TODO: Make UserDetail model
      res = self.get "/v1/user/detail", user_id: user_id
      response_error res, "user request failed" unless res.success?
      UserBox.from_json(res.body).user
    end

    def user_following(user_id : UInt64, restrict : Restrict = Restrict::Public, offset : UInt64? = nil) : UserQuery
      params = offset.nil? ? {} of String => UInt64 : {"offset" => offset}
      res = self.get "/v1/user/following", params, user_id: user_id, restrict: restrict
      response_error res, "user following request failed" unless res.success?
      UserQuery.from_json res.body
    end

    def user_followers(user_id : UInt64, offset : UInt64? = nil) : UserQuery
      params = offset.nil? ? {} of String => UInt64 : {"offset" => offset}
      res = self.get "/v1/user/follower", params, user_id: user_id
      response_error res, "user followers request failed" unless res.success?
      UserQuery.from_json res.body
    end

    def user_follow_add(user_id : UInt64, restrict : Restrict = Restrict::Public)
      res = self.post "/v1/user/follow/add", user_id: user_id, restrict: restrict
      response_error res, "user follow add request failed" unless res.success?
    end

    def user_follow_remove(user_id : UInt64)
      res = self.post "/v1/user/follow/delete", user_id: user_id
      response_error res, "user follow remove request failed" unless res.success?
    end

    # Internal structures

    private struct UserBox
      include JSON::Serializable

      property user : User
    end
  end

  # Public structures

  struct User
    include JSON::Serializable

    property id : UInt64
    property name : String
    property account : String
    property profile_image_urls : Avatar

    def initialize(@id, @name, @account, @profile_image_urls)
    end
  end

  struct Avatar
    include JSON::Serializable

    property medium : String

    def initialize(@medium)
    end

    def url : String
      self.medium
    end
  end
end
