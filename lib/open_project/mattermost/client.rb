# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "securerandom"

module OpenProject
  module Mattermost
    # Thin Mattermost REST client. Bot token auth. Create, update (bump),
    # thread replies, file upload, optional pin, /users/me for the test button.
    class Client
      Error = Class.new(StandardError)

      def initialize(server_url:, bot_token:)
        @server_url = server_url.to_s.strip.sub(%r{/+\z}, "").sub(%r{/api/v4\z}, "")
        @bot_token = bot_token.to_s.strip
      end

      def me
        request(:get, "/users/me")
      end

      def create_post(channel_id:, message:, props: {}, root_id: nil, file_ids: [])
        body = {
          channel_id: channel_id,
          message: message,
          props: props
        }
        body[:root_id] = root_id if root_id.present?
        body[:file_ids] = file_ids if file_ids.any?
        request(:post, "/posts", body)
      end

      # Rewrites the same post. Mattermost sets update_at, which UPs the card
      # in Threads and shows a new edited time on the message.
      def update_post(post_id:, message:, props: {})
        request(:put, "/posts/#{post_id}", {
                  id: post_id,
                  message: message,
                  props: props
                })
      end

      def pin_post(post_id)
        request(:post, "/posts/#{post_id}/pin", {})
      end

      def user_by_username(username)
        name = username.to_s.strip
        raise Error, "Mattermost username is blank" if name.blank?

        request(:get, "/users/username/#{URI.encode_www_form_component(name)}")
      end

      def user_by_email(email)
        addr = email.to_s.strip
        raise Error, "Mattermost email is blank" if addr.blank?

        request(:get, "/users/email/#{URI.encode_www_form_component(addr)}")
      end

      def find_user(username: nil, email: nil)
        errors = []
        [username.to_s.strip, username.to_s.strip.downcase].uniq.reject(&:blank?).each do |name|
          begin
            return user_by_username(name)
          rescue Error => e
            errors << "@#{name}: #{e.message}"
          end
        end
        if email.to_s.strip.present?
          begin
            return user_by_email(email.to_s.strip)
          rescue Error => e
            errors << email.to_s.strip + ": #{e.message}"
          end
        end
        raise Error,
              "No Mattermost user for OpenProject login #{username.inspect} / email #{email.inspect}. " \
              "#{errors.presence || 'Nothing to look up'}. " \
              "Mattermost username must match the OpenProject login, or the emails must match."
      end

      # Opens (or returns) a DM channel between this bot and the Mattermost user.
      def open_dm(username)
        open_direct(username: username)
      end

      def open_direct(username: nil, email: nil)
        other = find_user(username: username, email: email)
        bot = me
        raise Error, "Bot /users/me has no id" if bot["id"].blank?
        raise Error, "Mattermost user has no id" if other["id"].blank?

        channel = request(:post, "/channels/direct", [bot["id"], other["id"]])
        raise Error, "Mattermost DM channel has no id (#{channel.keys.first(8).join(',')})" if channel["id"].blank?

        channel["_resolved_username"] = other["username"]
        channel["_resolved_user_id"] = other["id"]
        channel["_resolved_email"] = other["email"]
        channel
      end

      def upload_file(channel_id:, filename:, io:, content_type: "application/octet-stream")
        uri = api_uri("/files?channel_id=#{URI.encode_www_form_component(channel_id)}")
        boundary = "opmm#{SecureRandom.hex(8)}"
        data = io.respond_to?(:read) ? io.read : io.to_s
        blob = +""
        blob << "--#{boundary}\r\n"
        blob << "Content-Disposition: form-data; name=\"files\"; filename=\"#{filename}\"\r\n"
        blob << "Content-Type: #{content_type}\r\n\r\n"
        blob << data
        blob << "\r\n--#{boundary}--\r\n"

        http = build_http(uri)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{@bot_token}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.body = blob
        parse(http.request(req))
      end

      def file_ids_from_upload(response)
        Array(response.dig("file_infos")).map { |info| info["id"] }.compact
      end

      private

      def request(method, path, body = nil)
        uri = api_uri(path)
        http = build_http(uri)
        klass = case method
                when :get then Net::HTTP::Get
                when :put then Net::HTTP::Put
                else Net::HTTP::Post
                end
        req = klass.new(uri)
        req["Authorization"] = "Bearer #{@bot_token}"
        if body
          req["Content-Type"] = "application/json"
          req.body = JSON.generate(body)
        end
        parse(http.request(req))
      end

      def build_http(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 15
        http
      end

      def api_uri(path)
        raise Error, "Mattermost server URL is blank" if @server_url.blank?
        raise Error, "Mattermost bot token is blank" if @bot_token.blank?

        URI.parse("#{@server_url}/api/v4#{path}")
      end

      def parse(res)
        json = res.body.present? ? JSON.parse(res.body) : {}
        unless res.is_a?(Net::HTTPSuccess)
          raise Error, "Mattermost #{res.code}: #{json['message'] || json['id'] || res.body}"
        end

        json
      rescue JSON::ParserError
        raise Error, "Mattermost #{res.code}: non-JSON body #{res.body.to_s[0, 200]}"
      end
    end
  end
end
