class Survey::Form < ActiveRecord::Base
  include Sys::Model::Base
  include Sys::Model::Rel::Unid
  include Cms::Model::Auth::Content

  STATE_OPTIONS = [['下書き保存', 'draft'], ['承認依頼', 'approvable'], ['即時公開', 'public']]
  CONFIRMATION_OPTIONS = [['あり', true], ['なし', false]]

  default_scope order("#{self.table_name}.sort_no IS NULL, #{self.table_name}.sort_no")

  # Content
  belongs_to :content, :foreign_key => :content_id, :class_name => 'Survey::Content::Form'
  validates_presence_of :content_id

  belongs_to :status, :foreign_key => :state, :class_name => 'Sys::Base::Status'
  validates_presence_of :state

  has_many :questions, :dependent => :destroy
  has_many :form_answers, :dependent => :destroy
  has_many :approval_requests, :class_name => 'Approval::ApprovalRequest', :as => :approvable, :dependent => :destroy

  validates :name, :presence => true, :uniqueness => true, :format => {with: /^[-\w]*$/}
  validates :title, :presence => true

  validate :open_period

  after_initialize :set_defaults

  scope :public, where(state: 'public')

  def public_questions
    questions.public
  end

  def open?
    now = Time.now
    return false if opened_at && opened_at > now
    return false if closed_at && closed_at < now
    return true
  end

  def state_options
    options = STATE_OPTIONS
    options.reject!{|o| o.last == 'public' } unless Core.user.has_auth?(:manager)
    options.reject!{|o| o.last == 'approvable' } unless content.approval_related?
    return options
  end

  def state_draft?
    state == 'draft'
  end

  def state_approvable?
    state == 'approvable'
  end

  def state_approved?
    state == 'approved'
  end

  def state_public?
    state == 'public'
  end

  def send_approval_request_mail
    approve_url = "#{content.site.full_uri.sub(/\/+$/, '')}#{Rails.application.routes.url_helpers.survey_form_path(content: content, id: id)}"

    approval_requests.each do |approval_request|
      approval_request.current_assignments.map{|a| a.user unless a.approved_at }.compact.each do |approver|
        next if approval_request.user.email.blank? || approver.email.blank?
        CommonMailer.approval_request(approval_request: approval_request, approve_url: approve_url,
                                      from: approval_request.user.email, to: approver.email).deliver
      end
    end
  end

  def send_approved_notification_mail
    publish_url = "#{content.site.full_uri.sub(/\/+$/, '')}#{Rails.application.routes.url_helpers.survey_form_path(content: content, id: id)}"

    approval_requests.each do |approval_request|
      next unless approval_request.finished?

      approver = approval_request.current_assignments.reorder('approved_at DESC').first.user
      next if approver.email.blank? || approval_request.user.email.blank?
      CommonMailer.approved_notification(approval_request: approval_request, publish_url: publish_url,
                                         from: approver.email, to: approval_request.user.email).deliver
    end
  end

  def approvers
    approval_requests.inject([]){|u, r| u | r.current_assignments.map{|a| a.user unless a.approved_at }.compact }
  end

  def approval_participators
    users = []
    approval_requests.each do |approval_request|
      users << approval_request.user
      approval_request.approval_flow.approvals.each do |approval|
        users.concat(approval.approvers)
      end
    end
    return users.uniq
  end

  def approve(user)
    return unless state_approvable?

    approval_requests.each do |approval_request|
      approval_request.approve(user) do |state|
        case state
        when 'progress'
          send_approval_request_mail
        when 'finish'
          send_approved_notification_mail
        end
      end
    end

    update_column(:state, 'approved') if approval_requests.all?{|r| r.finished? }
  end

  def publish
    return unless state_approved?
    approval_requests.destroy_all
    update_column(:state, 'public')
  end

  private

  def set_defaults
    self.state        = STATE_OPTIONS.first.last        if self.has_attribute?(:state) && self.state.nil?
    self.confirmation = CONFIRMATION_OPTIONS.first.last if self.has_attribute?(:confirmation) && self.confirmation.nil?
    self.sort_no      = 10 if self.has_attribute?(:sort_no) && self.sort_no.nil?
  end

  def open_period
    return if opened_at.blank? || closed_at.blank?
    errors.add(:opened_at, "が#{self.class.human_attribute_name :closed_at}を過ぎています。") if closed_at < opened_at
  end
end
