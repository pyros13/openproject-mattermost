# frozen_string_literal: true

module OpenProject
  module Mattermost
    # Everyone related to the work package: author, assignee, accountable,
    # watchers, group members of those roles, plus any extra users passed in
    # (journal author, people we already DM'd).
    class Recipients
      Member = Struct.new(:user, :username, keyword_init: true)

      def self.members(work_package, extra_users: [])
        users = []
        wp = fresh(work_package)
        users.concat expand(wp.try(:author))
        users.concat expand(wp.try(:assigned_to))
        users.concat expand(wp.try(:responsible)) if wp.respond_to?(:responsible)
        users.concat watcher_principals(wp)
        Array(extra_users).each { |user| users.concat expand(user) }

        users.compact.uniq { |user| user.try(:id) || user.object_id }.filter_map do |user|
          next if skipped_principal?(user)

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

      def self.fresh(work_package)
        return work_package unless work_package.respond_to?(:reload) && work_package.try(:persisted?)

        work_package.reload
      rescue StandardError
        work_package
      end

      def self.watcher_principals(work_package)
        list = []
        if work_package.respond_to?(:watcher_users)
          list.concat Array(work_package.watcher_users)
        end
        if list.empty? && work_package.respond_to?(:watchers)
          Array(work_package.watchers).each do |watcher|
            list.concat expand(watcher.try(:user) || watcher)
          end
        end
        list
      rescue StandardError
        []
      end

      def self.expand(principal)
        return [] if principal.nil? || skipped_principal?(principal)
        return Array(group_users(principal)) if group?(principal)

        [principal]
      end

      def self.group?(principal)
        return false if principal.nil?
        return true if principal.class.name == "Group"
        return true if principal.try(:type).to_s == "Group"

        false
      end

      def self.group_users(principal)
        if principal.respond_to?(:users)
          Array(principal.users)
        elsif principal.respond_to?(:group_users)
          Array(principal.group_users).map { |row| row.try(:user) || row }
        else
          []
        end
      rescue StandardError
        []
      end

      def self.skipped_principal?(principal)
        return true if principal.nil?
        return true if principal.try(:anonymous?)
        return true if principal.try(:deleted?)
        return true if principal.try(:status).to_s == "locked"
        return true if principal.try(:status).to_s == "deleted"

        false
      end
    end
  end
end
