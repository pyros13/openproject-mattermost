# frozen_string_literal: true

class MattermostWorkPackagePost < ApplicationRecord
  belongs_to :work_package

  validates :post_id, presence: true
  validates :channel_id, presence: true
end
