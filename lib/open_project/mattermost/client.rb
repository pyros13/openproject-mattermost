# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OpenProject
  module Mattermost
    # Thin Mattermost REST client. Bot token auth. Create, update (bump),
    # thread replies, file upload, optional pin.
    class Client
      Error = Class.new(StandardError)

      def initialize(server_url:, bot_token:)
        @server_url = server_url.to_s.sub(%r{/+\z}, "").sub(%r{/api/v4\z}, "")
        @bot_token = bot_token.to_s
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

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
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

      def request(method, path, body)
        uri = api_uri(path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        klass = method == :put ? Net::HTTP::Put : Net::HTTP::Post
        req = klass.new(uri)
        req["Authorization"] = "Bearer #{@bot_token}"
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
        parse(http.request(req))
      end

      def api_uri(path)
        URI.parse("#{@server_url}/api/v4#{path}")
      end

      def parse(res)
        json = res.body.present? ? JSON.parse(res.body) : {}
        unless res.is_a?(Net::HTTPSuccess)
          raise Error, "Mattermost #{res.code}: #{json['message'] || res.body}"
        end

        json
      end
    end
  end
end
