# One line of a trip's plan: a train, a stay, something to do, on a day and
# optionally at a time and a place. It carries no money; what a trip costs
# lives in the project's transactions and IOUs.
class ItineraryItem < ApplicationRecord
  KINDS = %w[train bus flight drive stay activity food other].freeze
  KIND_ICONS = {
    "train" => "train-front",
    "bus" => "bus",
    "flight" => "plane",
    "drive" => "car",
    "stay" => "bed",
    "activity" => "map-pin",
    "food" => "utensils",
    "other" => "circle-dot"
  }.freeze
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  belongs_to :project

  before_validation :blank_to_nil

  validates :kind, inclusion: { in: KINDS }
  validates :title, presence: true, length: { maximum: 255 }
  validates :starts_on, presence: true
  validates :time_of_day, format: { with: TIME_FORMAT }, allow_nil: true
  validates :location, :reference, length: { maximum: 255 }
  validate :ends_after_start

  # By day, then by time. Lines without a time come after the timed ones, in
  # the order they were added.
  scope :chronological, -> {
    order(:starts_on, Arel.sql("itinerary_items.time_of_day IS NULL, itinerary_items.time_of_day"), :created_at)
  }

  def icon
    KIND_ICONS.fetch(kind, "circle-dot")
  end

  # A stay, or anything else that runs past the day it starts.
  def multi_day?
    ends_on.present? && ends_on > starts_on
  end

  private
    def blank_to_nil
      %i[time_of_day location reference notes].each do |attribute|
        self[attribute] = self[attribute].presence&.strip
      end
      # A time field can submit "09:30:00"; keep hours and minutes.
      self.time_of_day = time_of_day[0, 5] if time_of_day.to_s.match?(/\A\d\d:\d\d:\d\d/)
    end

    def ends_after_start
      return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

      errors.add(:ends_on, :before_start)
    end
end
