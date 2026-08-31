# frozen_string_literal: true

module OpenProject
  module Mattermost
    # People on a work package who should get a private Mattermost message
    # when the project is set to "per user" or "both".
    class Recipients
      Member = Struct.new(:user, :username, keyword_init: true)

      def self.members(work_package)
        users = []
        users << work_package.try(:author)
        users << work_package.try(:assigned_to)
        users << work_package.try(:responsible) if work_package.respond_to?(:responsible)
        if work_package.respond_to?(:watchers)
          Array(work_package.watchers).each do |watcher|
            users << (watcher.try(:user) || watcher)
          end
        end

        users.compact.uniq { |user| user.try(:id) || user.object_id }.filter_map do |user|
          username = username_for(user)
          next if username.blank?

          Member.new(user: user, username: username)
        end
      end

      def self.username_for(user)
        return if user.nil?

        [
          user.try(:login),
          user.try(:mail).to_s.split("@").first
        ].map { |value| value.to_s.strip.downcase.presence }.compact.first
      end
    end
  end
end
