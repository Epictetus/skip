# SKIP(Social Knowledge & Innovation Platform)
# Copyright (C) 2008-2010 TIS Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

class BoardEntry < ActiveRecord::Base

  include Publication
  include ActionController::UrlWriter
  include Search::Indexable

  belongs_to :tenant
  belongs_to :user
  belongs_to :owner, :polymorphic => true
  has_many :tags, :through => :entry_tags
  has_many :entry_tags, :dependent => :destroy
  has_many :entry_trackbacks, :dependent => :destroy
  has_many :to_entry_trackbacks, :class_name => "EntryTrackback", :foreign_key => :tb_entry_id, :dependent => :destroy
  has_many :board_entry_comments, :dependent => :destroy
  has_many :entry_hide_operations, :dependent => :destroy
  has_one  :state, :class_name => "BoardEntryPoint", :dependent => :destroy
  has_many :entry_accesses, :dependent => :destroy
  has_many :user_readings, :dependent => :destroy

  validates_presence_of :title
  validates_presence_of :contents
  validates_presence_of :date
  validates_presence_of :user
  validates_presence_of :tenant
  validates_presence_of :owner
  validates_presence_of :last_updated

  validates_length_of   :title, :maximum => 100

  AIM_TYPES = %w(entry question).freeze
  HIDABLE_AIM_TYPES = %w(question).freeze
  TIMLINE_AIM_TYPES = %w(entry).freeze
  validates_inclusion_of :aim_type, :in => AIM_TYPES
  validates_inclusion_of :publication_type, :in => %w(private public)

  # TODO 回帰テストを書く
  named_scope :accessible, proc { |user|
    if joined_group_ids = Group.active.participating(user).map(&:id) and !joined_group_ids.empty?
      { :conditions => ['board_entries.tenant_id = ? AND publication_type = "public" OR owner_id IN (?)', user.tenant_id, joined_group_ids] }
    else
      { :conditions => ['board_entries.tenant_id = ? AND publication_type = "public"', user.tenant_id] }
    end
  }

  named_scope :category_like, proc { |category|
    { :conditions => ['category like :category', { :category => "%[#{category}]%" }] }
  }

  named_scope :category_not_like, proc { |category|
    { :conditions => ['category not like :category', { :category => "%[#{category}]%" }] }
  }

  named_scope :group_category_eq, proc { |category_code|
    category = GroupCategory.find_by_code(category_code)
    return {} unless category
    group_symbols = Group.active.categorized(category.id).all.map(&:symbol)
    { :conditions => ['board_entries.symbol IN (?)', group_symbols] }
  }

  named_scope :recent, proc { |milliseconds|
    return {} if milliseconds.blank?
    { :conditions => ['last_updated > :date', { :date => Time.now.ago(milliseconds) }] }
  }

  named_scope :recent_with_comments, proc { |milliseconds|
    return {} if milliseconds.blank?
    {
      :conditions => ['last_updated > :date OR board_entry_comments.updated_on > :date', { :date => Time.now.ago(milliseconds) }],
      :include => :board_entry_comments
    }
  }

  named_scope :diary, proc {
    { :conditions => ['entry_type = ?', BoardEntry::DIARY] }
  }

  named_scope :active_user, proc {
    { :conditions => ['user_id IN (?)', User.active.map(&:id).uniq] }
  }

  named_scope :owned, proc {|owner|
    { :conditions => ['board_entries.owner_id = ? AND board_entries.owner_type = ?', owner.id, owner.class.name] }
  }

  named_scope :question, proc { { :conditions => ['board_entries.aim_type = \'question\''] } }
  named_scope :timeline, proc { { :conditions => ['board_entries.aim_type = \'entry\''] } }
  named_scope :visible, proc { { :conditions => ['board_entries.hide = ?', false] } }

  named_scope :unread, proc { |user|
    {
      :conditions => ['user_readings.read = ? AND user_readings.user_id = ?', false, user.id],
      :include => [:user_readings]
    }
  }

  named_scope :unread_only_notice, proc { |user|
    {
      :conditions => ['user_readings.read = ? AND user_readings.user_id = ? AND user_readings.notice_type = "notice"', false, user.id],
      :include => [:user_readings]
    }
  }

  named_scope :commented, proc { |user|
    {
      :conditions => ['board_entry_comments.user_id = ?', user.id],
      :include => [:board_entry_comments]
    }
  }

  named_scope :read, proc { |user|
    {
      :conditions => ['user_readings.read = ? AND user_readings.user_id = ?', true, user.id],
      :include => [:user_readings]
    }
  }

  named_scope :tagged, proc { |tag_words, tag_select|
    return {} if tag_words.blank?
    tag_select = 'AND' unless tag_select == 'OR'
    condition_str = ''
    condition_params = []
    words = tag_words.split(',')
    words.each do |word|
      condition_str << (word == words.last ? ' board_entries.category like ?' : " board_entries.category like ? #{tag_select}")
      condition_params << SkipUtil.to_like_query_string(word)
    end
    { :conditions => [condition_str, condition_params].flatten }
  }

  alias_scope :selected_owner_type, proc { |owner_type|
    if owner_type == 'User' || owner_type == 'Group'
      owner_type_is(owner_type)
    else
      scoped({})
    end
  }

  alias_scope :owner_type_is_group, proc { |owner_type_is_group|
    owner_type_is_group == '1' ? owner_type_is('Group') : scoped({})
  }

  named_scope :from_recents, proc {
    num = GlobalInitialSetting['mypage_entry_search_limit'] || 1000
    { :from => "(SELECT * FROM board_entries ORDER BY board_entries.last_updated DESC LIMIT #{num}) AS board_entries" }
  }

  named_scope :order_new, proc {
    { :order => "last_updated DESC, board_entries.id DESC" }
  }

  named_scope :order_old, proc {
    { :order => "last_updated ASC, board_entries.id ASC" }
  }

  named_scope :order_new_include_comment, proc {
    { :order => "board_entries.updated_on DESC,board_entries.id DESC" }
  }

  named_scope :order_access, proc {
    { :order => 'board_entry_points.access_count DESC', :include => [:state] }
  }

  named_scope :order_point, proc {
    { :order => 'board_entry_points.point DESC', :include => [:state] }
  }

  named_scope :aim_type, proc { |types|
    return {} if types.blank?
    types = types.split(',').map(&:strip) if types.is_a?(String)
    { :conditions => ['aim_type IN (?)', types] }
  }

  named_scope :order_sort_type, proc { |sort_type|
    case sort_type
    when "date" then self.order_new_include_comment.proxy_options
    when "access" then self.order_access.proxy_options
    when "point" then self.order_point.proxy_options
    end
  }

  named_scope :limit, proc { |num| { :limit => num } }

  attr_accessor :send_mail, :contents_hiki, :contents_richtext

  N_('BoardEntry|Entry type|DIARY')
  N_('BoardEntry|Entry type|GROUP_BBS')
  ns_('BoardEntry|Aim type|entry', 'entries', 1)
  ns_('BoardEntry|Aim type|question', 'questions', 1)
  N_('BoardEntry|Aim type|Desc|entry')
  N_('BoardEntry|Aim type|Desc|question')
  N_('BoardEntry|Open|true')
  N_('BoardEntry|Open|false')
  DIARY = 'DIARY'
  GROUP_BBS = 'GROUP_BBS'

  def validate
#    symbol_type, symbol_id = SkipUtil.split_symbol self.symbol
#    if self.entry_type == DIARY
#      if symbol_type == "uid"
#        errors.add_to_base(_("User does not exist.")) unless User.find_by_uid(symbol_id)
#      else
#        errors.add_to_base(_("Invalid user detected."))
#      end
#    elsif self.entry_type == GROUP_BBS
#      if symbol_type == "gid"
#        errors.add_to_base(_("Group does not exist.")) unless Group.active.find_by_gid(symbol_id)
#      else
#        errors.add_to_base(_("Invalid group detected."))
#      end
#    end

    Tag.validate_tags(category).each{ |error| errors.add(:category, error) }
  end

  def before_create
    generate_next_user_entry_no
  end

  def after_create
    BoardEntryPoint.create(:board_entry_id=>id)
  end

  def after_save
    Tag.create_by_comma_tags category, entry_tags
  end

  # TODO 回帰テストを書く
  # TODO ShareFileと統合したい
  def full_accessible? target_user = self.user
    case
    when self.owner_is_user? then self.writer?(target_user)
    when self.owner_is_group? then owner.owned?(target_user) || (owner.joined?(target_user) && self.writer?(target_user))
    else
      false
    end
  end

  # TODO 回帰テストを書く
  # TODO ShareFileと統合したい
  def accessible? target_user = self.user
    case
    when self.owner_is_user? then self.public? || self.writer?(target_user)
    when self.owner_is_group? then self.public? || owner.joind?(target_user)
    else
      false
    end
  end

  # TODO ShareFileと統合したい
  def accessible_without_writer? target_user = self.user
    !self.writer?(target_user) && self.accessible?(target_user)
  end

  # TODO ShareFileと統合したい
  def writer? target_user_or_target_user_id
    case
    when target_user_or_target_user_id.is_a?(User) then user_id == target_user_or_target_user_id.id
    when target_user_or_target_user_id.is_a?(Integer) then user_id == target_user_or_target_user_id
    else
      false
    end
  end

  # TODO ShareFileと統合したい
  # 所属するグループの公開範囲により、記事の公開範囲を判定する
  def owner_is_public?
    !(owner.is_a?(Group) && owner.protected?)
  end

  # TODO ShareFileと統合したい
  def owner_is_user?
    owner.is_a?(User)
  end

  # TODO ShareFileと統合したい
  def owner_is_group?
    owner.is_a?(Group)
  end

  def self.unescape_href text
    text.gsub(/<a[^>]*href=[\'\"](.*?)[\'\"]>/){ CGI.unescapeHTML($&) } if text
  end

#  def permalink
#    '/page/' + id.to_s
#  end

  def diary?
    entry_type == DIARY
  end

  def hiki?
    editor_mode == 'hiki'
  end

  def prev_accessible target_user
    BoardEntry.accessible(target_user).last_updated_lt(self.last_updated).id_lt(self.id).order_new.first
  end

  def next_accessible target_user
    BoardEntry.accessible(target_user).last_updated_gt(self.last_updated).id_gt(self.id).order_old.first
  end

  # TODO Tagのnamed_scopeにしてなくしたい
  def self.get_popular_tag_words()
    options = { :select => 'tags.name',
                :joins => 'JOIN tags ON entry_tags.tag_id = tags.id',
                :group => 'entry_tags.tag_id',
                :order => 'count(entry_tags.tag_id) DESC'}

    entry_tags = EntryTag.find(:all, options)
    tags = []
    entry_tags.each do |tag|
      tags << tag.name
    end
    return tags.uniq.first(40)
  end

  def self.categories_hash user
    accessible_entries = BoardEntry.accessible(user).descend_by_last_updated
    accessible_entry_ids = accessible_entries.map(&:id)
    user_wrote_entry_ids = accessible_entries.select {|e| e.user_id == user.id}.map(&:id)

    user_wrote_tags = Tag.uniq_by_entry_ids(user_wrote_entry_ids).ascend_by_name.map(&:name)
    recent_user_accessible_tags = Tag.uniq_by_entry_ids(accessible_entry_ids[0..9]).ascend_by_name.map(&:name)
    standard_tags = Tag.get_standard_tags

    categories_hash = {}
    categories_hash[:standard] = standard_tags
    categories_hash[:mine] = user_wrote_tags - standard_tags
    categories_hash[:user] = recent_user_accessible_tags - (user_wrote_tags + standard_tags)
    categories_hash
  end

  def diary_date
    format = _("%B %d %Y")
    unless ignore_times
      format = _("%B %d %Y %H:%M")
    end
    date.strftime(format)
  end

  def diary_author
    unless diary?
      "by " + user.name if user
    end
  end

  # TODO ShareFileと統合したい, helperに持ちたい
  def visibility
    text = color = ""
    if public?
      text = _("[Open to all]")
      color = "yellow"
    elsif private?
      if diary?
        text = _("[Owner only]")
      else
        text = _("[Group members only]")
      end
      color = "#FFDD75"
    end
    [text, color]
  end

  # TODO もはやprepareじゃない。sent_contact_mailsなどにリネームする
  def send_contact_mails
    return unless self.send_mail?
    return if diary? && private?
    return if !Admin::Setting.enable_send_email_to_all_users(tenant) && public?

    users = publication_users
    users.each do |u|
      next if u.id == self.user_id
      UserMailer::AR.deliver_sent_contact(u.email, self.owner, self)
    end
  end

  def send_mail?
    true if send_mail == "1"
  end

#  # 権限チェック
#  # この記事が編集可能かどうかを判断する
#  def editable?(login_user_symbols, login_user_id, login_user_symbol, login_user_groups)
#    # 所有者がマイユーザ
#    return true if login_user_symbol == symbol
#
#    #  マイユーザ/マイグループが公開範囲指定対象で、編集可能
#    return true if publicate?(login_user_symbols) && edit?(login_user_symbols)
#
#    # 所有者がマイグループ AND 作成者がマイユーザ
#    if login_user_groups.include?(symbol)
#      return true if login_user_id == user_id
#      #  AND グループ管理者がマイユーザ
#      group = Symbol.get_item_by_symbol(symbol)
#      return true if publicate?(login_user_symbols) && group.owners.any?{|user| user.id == login_user_id}
#    end
#    return false
#  end
#
#  # FIXME:editable?へのマージと、edit?の廃止
#  def will_editable?(login_user)
#    editable?(login_user.belong_symbols, login_user.id, login_user.symbol, login_user.group_symbols)
#  end

#  def publicate? login_user_symbols
#    entry_publications.any? {|publication| login_user_symbols.include?(publication.symbol) || "sid:allusers" == publication.symbol}
#  end
#
#  # TODO editable?とどちらかにしたい。
#  def edit? login_user_symbols
#    entry_editors.any? {|editor| login_user_symbols.include? editor.symbol }
#  end

  # アクセスしたことを示す（アクセス履歴）
  def accessed(login_user_id)
    unless writer?(login_user_id)
      state.increment(:access_count)
      state.increment(:today_access_count)
      state.save

      if today_entry= EntryAccess.find(:first, :conditions =>["board_entry_id = ? and updated_on > ? and visitor_id = ?", id, Date.today, login_user_id])
        today_entry.destroy
      end
      # FIXME: 管理機能で足跡の件数を減らしたときに、これまでの最大数の足跡がついたものは、減らない
      # レアケースなので、一旦PEND
      if  EntryAccess.count(:conditions => ["board_entry_id = ?", id]) >= Admin::Setting.access_record_limit(self.tenant)
        EntryAccess.find(:first, :conditions => ["board_entry_id = ?", id], :order => "updated_on ASC").destroy
      end
      EntryAccess.create(:board_entry_id => id, :visitor_id => login_user_id)
    end
    UserReading.create_or_update(login_user_id, self.id)
  end

  def send_trackbacks!(user, comma_tb_ids)
    tb_entries = BoardEntry.accessible(user).id_is(comma_tb_ids.split(',').map(&:strip))
    current_tb_entries = to_entry_trackbacks.map(&:board_entry)
    # 登録済みのトラバが今回未送信(=> 削除する)
    to_entry_trackbacks.each do |entry_trackback|
      entry_trackback.destroy if (current_tb_entries - tb_entries).include?(entry_trackback.board_entry)
    end

    # 未登録のトラバ(=> 作成する)
    (tb_entries - current_tb_entries).each do |entry|
      to_entry_trackbacks.create!(:board_entry_id => entry.id)
      unless entry.user_id == user.id
        SystemMessage.create_message :message_type => 'TRACKBACK', :user_id => entry.user_id, :message_hash => {:board_entry_id => entry.id}
      end
    end
  end

  # この記事の公開対象ユーザ一覧を返す
  # 戻り値：Userオブジェクトの配列（重複なし）
  def publication_users
    case self.publication_type
    when "private"
      if self.owner.is_a?(Group)
        # FIXME これって参加者になってないよね?
        self.owner.users.active
      elsif self.owner.is_a?(User)
        [self.owner]
      else
        []
      end
    when "public"
      self.tenant.users.active.all
    else
      []
    end
  end

  def root_comments
    board_entry_comments.find(:all, :conditions => ["parent_id is NULL"], :order => "created_on")
  end
#
#  # TODO Symbol.get_item_by_symbolとかぶってる。こちらを生かしたい
#  # TODO ShareFileと統合したい
#  def self.owner symbol
#    return nil if symbol.blank?
#    symbol_type, symbol_id = SkipUtil::split_symbol symbol
#    if symbol_type == "uid"
#      User.find_by_uid(symbol_id)
#    elsif symbol_type == "gid"
#      Group.active.find_by_gid(symbol_id)
#    else
#      nil
#    end
#  end
#
#  # TODO ShareFileと統合したい, ownerにしたい
#  def load_owner
#    @owner = self.class.owner self.symbol
#  end

  def toggle_hide(user)
    unless BoardEntry::HIDABLE_AIM_TYPES.include? self.aim_type
      self.errors.add_to_base(_("Invalid operation."))
      return false
    end
    transaction do
      self.toggle!(:hide)
      self.entry_hide_operations.create!(:user => user, :operation_type => self.hide.to_s)
      SystemMessage.create_message :message_type => 'QUESTION', :user_id => self.user_id, :message_hash => {:board_entry_id => self.id} unless user.id == self.user_id
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    self.errors.add_to_base(e.errors.full_messages)
    false
  end

  AIM_TYPES.each do |type|
    define_method("is_#{type.downcase}?") do
      self.aim_type == type
    end
    define_method("be_#{type.downcase}") do
      self.aim_type = type
    end
    define_method("be_#{type.downcase}!") do
      self.aim_type = type
      self.save!
    end
  end

  def self.enable_aim_types tenant
    AIM_TYPES
  end

  def be_close!
    return false unless diary?
    self.publication_type = 'private'
    self.save!
    true
  end

  def self.be_hide_too_old options = {}
    options = {:day_before => 30}.merge!(options)
    BoardEntry.aim_type_is('question').hide_is(false).created_on_lt(Time.now.ago(options[:day_before].to_i.day)).update_all('hide = 1')
  end

  def reflect_user_readings
    user_ids = []
    Notice.subscribed(owner).each { |notice| user_ids << notice.user_id }
    if self.owner_is_group?
      owner.group_participations.active.each { |gp| user_ids << gp.id }
    end
    User.id_is(user_ids.uniq).each do |user|
      reflect_user_reading(user)
    end
  end

  def reflect_user_reading notice_user
    return if notice_user.id == self.user.id
    return unless self.accessible?(notice_user)

    if user_reading = self.user_readings.checked_on_lt(self.last_updated).find_or_initialize_by_user_id(notice_user.id)
      params = {:read => false, :checked_on => nil, :notice_type => nil}
      user_reading.attributes = params
      user_reading.save
    end
  end

  def to_draft uri
    body_lines = []
    body_lines << ERB::Util.h(self.title)
    body_lines << ERB::Util.h(self.category)
    body_lines << ERB::Util.h(self.user.name)
    body_lines << (self.editor_mode == 'hiki' ? convert_hiki_to_html(self.contents) : self.contents)

    self.board_entry_comments.each do|comment|
      body_lines << ERB::Util.h(comment.user.name)
      body_lines << convert_hiki_to_html(comment.contents)
    end
    self.entry_trackbacks.each do |trackback|
      body_lines << ERB::Util.h(trackback.tb_entry.user.name)
      body_lines << trackback.tb_entry.title
    end
<<-DRAFT
@uri=#{uri}
@title=#{ERB::Util.h(self.title)}
@auther=#{ERB::Util.h(self.user.name)}
@cdate=#{self.created_on.rfc822}
@mdate=#{self.last_updated.rfc822}
@aid=skip
@object_type=#{self.class.table_name.singularize}
@object_id=#{self.id}

#{body_lines.join("\n")}
DRAFT
  end

  def convert_hiki_to_html hiki_text
    HikiDoc.new((hiki_text || ''), '').to_html
  end

private
  def generate_next_user_entry_no
    entry = BoardEntry.find(:first,
                            :select => 'max(user_entry_no) max_user_entry_no',
                            :conditions =>['user_id = ?', self.user_id])
    self.user_entry_no = entry.max_user_entry_no.to_i + 1
  end
end
