# encoding: utf-8
class Gnav::Content::Setting < Cms::ContentSetting
  set_config :gp_category_content_category_type_id, :name => '汎用カテゴリタイプ',
    :options => GpCategory::Content::CategoryType.all.map{|ct| [ct.name, ct.id] }
  set_config :list_style, :name => "#{GpArticle::Doc.model_name.human}表示形式",
    :comment => '日付：@date タイトル：@title 組織：@group'
  set_config :date_style, :name => "#{GpArticle::Doc.model_name.human}日付形式",
    :comment => '年：%Y 月：%m 日：%d 時：%H 分：%M 秒：%S'

  after_initialize :set_defaults

  def upper_text
  end

  def lower_text
  end

  private

  def set_defaults
    self.value = '@title(@date @group)' if self.name == 'list_style' && self.value.nil?
    self.value = '%Y年%m月%d日 %H時%M分' if self.name == 'date_style' && self.value.nil?
  rescue ActiveModel::MissingAttributeError => evar
    logger.warn(evar.message)
  end
end
