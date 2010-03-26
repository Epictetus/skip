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

require 'jcode'
require 'open-uri'
require "resolv-replace"
require 'timeout'
require 'feed-normalizer'
class MypagesController < ApplicationController
  before_filter :setup_layout
  before_filter :load_user

  verify :method => :post, :only => [ :change_read_state], :redirect_to => { :action => :index }

  helper_method :recent_day

  # ================================================================================
  #  tab menu actions
  # ================================================================================

  # mypage > home
  def index
    # ============================================================
    #  right side area
    # ============================================================
    @year, @month, @day = parse_date
    @recent_groups =  Group.active.recent(recent_day).order_recent.limit(5)
    @recent_users = User.recent(recent_day).order_recent.limit(5) - [current_user]

    # ============================================================
    #  main area entries
    # ============================================================
    @questions = find_questions_as_locals({:recent_day => recent_day})
    @access_blogs_cache_key = "access_blog_#{Time.now.strftime('%Y%m%d%H')}"
    # access_blogの取得は複数tableのカラムを伴うソートをするため非常に重くなる
    # mysqlの実行計画ではUsing temporaryになる最悪のパターン
    # 毎回取得する必要性は低いため1時間に1度フラグメントキャッシュを用いてキャッシュしておくことにする
    unless read_fragment(@access_blogs_cache_key)
      expire_fragment_without_locale("access_blog_#{Time.now.ago(1.hour).strftime('%Y%m%d%H')}") # 古いcacheの除去
      @access_blogs = find_access_blogs_as_locals({:per_page => 10})
    end
    @recent_blogs = find_recent_blogs_as_locals({:per_page => per_page})
    @timelines = find_timelines_as_locals({:per_page => per_page}) if current_user.custom.display_entries_format == 'tabs'
    @recent_bbs = recent_bbs

  end

  # mypage > trace(足跡)
  def trace
    @access_count = current_user.user_access.access_count
    @access_tracks = current_user.tracks
  end

  # ================================================================================
  #  mypage > home 関連
  # ================================================================================

  # 公開されている記事一覧画面を表示
  def entries
    unless valid_list_types.include?(params[:list_type])
      redirect_to [current_tenant, :board_entries]
      return
    end
    locals = find_as_locals(params[:list_type], {:per_page => 20})
    @id_name = locals[:id_name]
    @title_icon = locals[:title_icon]
    @title_name = locals[:title_name]
    @entries = locals[:pages]
  end

  # アンテナ毎の記事一覧画面を表示
  def entries_by_antenna
    @antenna_entry = antenna_entry(params[:target_type], params[:target_id], params[:read])
    @antenna_entry.title = antenna_entry_title(@antenna_entry)
    if @antenna_entry.need_search?
      @entries = @antenna_entry.scope.order_new.paginate(:page => params[:page], :per_page => 20)
      @user_unreadings = unread_entry_id_hash_with_user_reading(@entries.map {|entry| entry.id}, params[:target_type])
    end
  end

  # ajax_action
  # 未読・既読を変更する
  def change_read_state
    ur = UserReading.create_or_update(session[:user_id], params[:board_entry_id], params[:read])
    render :text => ur.read? ? _('Entry was successfully marked read.') : _('Entry was successfully marked unread.')
  end

  # ajax_action
  # [公開された記事]のページ切り替えを行う。
  # param[:target]で指定した内容をページ単位表示する
  def load_entries
    option = { :per_page => per_page }
    option[:recent_day] = params[:recent_day].to_i if params[:recent_day]
    save_current_page_to_cookie
    render :partial => params[:page_name], :locals => find_as_locals(params[:target], option)
  end

  # ajax_action
  # 右側サイドバーのRSSフィードを読み込む
  def load_rss_feed
    render :partial => "rss_feed", :locals => { :feeds => unifed_feeds }
  rescue Timeout::Error
    render :text => _("Timeout while loading rss.")
    return false
  rescue Exception => e
    logger.error e
    e.backtrace.each { |line| logger.error line}
    render :text => _("Failed to load rss.")
    return false
  end

  # [最近]を表す日数
  def recent_day
    10
  end

  private
  def per_page
    current_user.custom.display_entries_format == 'tabs' ? Admin::Setting.entry_showed_tab_limit_per_page(current_tenant) : 8
  end

  def setup_layout
    @main_menu = @title = _('My Page')
  end

  # 日付情報を解析して返す。
  def parse_date
    year = params[:year] ? params[:year].to_i : Time.now.year
    month = params[:month] ? params[:month].to_i : Time.now.month
    day = params[:day] ? params[:day].to_i : Time.now.day
    unless Date.valid_date?(year, month, day)
      year, month, day = Time.now.year, Time.now.month, Time.now.day
    end
    return year, month, day
  end

  def antenna_entry(key, target_id = nil, read = true)
    unless key.blank?
      if target_id
        if %w(user group).include?(key)
          UserAntennaEntry.new(current_user, key, target_id, read)
        else
          raise ActiveRecord::RecordNotFound
        end
      else
        if %w(message comment joined_group).include?(key)
          SystemAntennaEntry.new(current_user, key, read)
        else
          raise ActiveRecord::RecordNotFound
        end
      end
    else
      AntennaEntry.new(current_user, read)
    end
  end

  class AntennaEntry
    attr_reader :key, :antenna
    attr_accessor :title

    def initialize(current_user, read = true)
      @read = read
      @current_user = current_user
    end

    def scope
      scope = BoardEntry.accessible(@current_user)
      scope = scope.unread(@current_user) unless @read
      scope
    end

    def need_search?
      true
    end
  end

  class SystemAntennaEntry < AntennaEntry
    def initialize(current_user, key, read = true)
      @current_user = current_user
      @key = key
      @read = read
    end

    def scope
      scope = case
              when @key == 'message'  then BoardEntry.accessible(@current_user).notice
              when @key == 'comment'  then BoardEntry.accessible(@current_user).commented(@current_user)
              when @key == 'joined_group'    then Group.active.participating(@current_user).owner_entries.accessible(@current_user)
              end

      unless @read
        if @key == 'message'
          scope = scope.unread_only_notice(@current_user)
        else
          scope = scope.unread(@current_user)
        end
      end
      scope
    end

    def need_search?
      !(@key == 'group' && @current_user.group_symbols.size == 0)
    end
  end

  class UserAntennaEntry < AntennaEntry
    def initialize(current_user, type, id, read = true)
      @current_user = current_user
      @type = type
      @read = read
      @owner = type.humanize.constantize.find id
      @title = @owner.name
    end

    def scope
      scope = BoardEntry.accessible(@current_user).owned(@owner)
      scope = scope.unread(@current_user) unless @read
      scope
    end

    def need_search?
      true
    end
  end

  def find_as_locals target, options
    group_categories = GroupCategory.all.map{ |gc| gc.code.downcase }
    case
    when target == 'questions'             then find_questions_as_locals options
    when target == 'access_blogs'          then find_access_blogs_as_locals options
    when target == 'recent_blogs'          then find_recent_blogs_as_locals options
    when target == 'timelines'             then find_timelines_as_locals options
    when group_categories.include?(target) then find_recent_bbs_as_locals target, options
# TODO 例外出すなどの対応をしないとアプリケーションエラーになってしまう。
#    else
    end
  end

  # 質問記事一覧を取得する（partial用のオプションを返す）
  def find_questions_as_locals options
    pages = BoardEntry.from_recents.question.visible.accessible(current_user).order_new.scoped(:include => [:state, :user])

    locals = {
      :id_name => 'questions',
      :title_icon => "user_comment",
      :title_name => _('Recent Questions'),
      :pages => pages,
      :per_page => options[:per_page],
      :recent_day => options[:recent_day]
    }
  end

  # 最近の人気記事一覧を取得する（partial用のオプションを返す）
  def find_access_blogs_as_locals options
    pages = BoardEntry.accessible(current_user).scoped(
      :order => "board_entry_points.access_count DESC, board_entries.last_updated DESC, board_entries.id DESC",
      :include => [ :user, :state ]
    ).timeline.diary.recent(recent_day.day).paginate(:page => params[:page], :per_page => options[:per_page])

    locals = {
      :title_name => _('Recent Popular Blogs'),
      :per_page => options[:per_page],
      :pages => pages
    }
  end

  # 記事一覧を取得する（partial用のオプションを返す）
  def find_recent_blogs_as_locals options
    id_name = 'recent_blogs'
    pages = BoardEntry.from_recents.accessible(current_user).entry_type_is(BoardEntry::DIARY).timeline.scoped(:include => [ :user, :state ]).order_new.paginate(:page => target_page(id_name), :per_page => options[:per_page])

    locals = {
      :id_name => id_name,
      :title_icon => "user",
      :title_name => _('Blogs'),
      :pages => pages,
      :per_page => options[:per_page]
    }
  end

  def find_timelines_as_locals options
    id_name = 'timelines'
    pages = BoardEntry.from_recents.accessible(current_user).timeline.order_new.scoped(:include => [:state, :user]).paginate(:page => target_page(id_name), :per_page => options[:per_page])
    locals = {
      :id_name => id_name,
      :title_name => _('See all'),
      :per_page => options[:per_page],
      :pages => pages
    }
  end

  # BBS記事一覧を取得するメソッドを動的に生成(partial用のオプションを返す)
  def find_recent_bbs_as_locals code, options = {}
    category = GroupCategory.find_by_code(code)
    id_name = category.code.downcase
    pages = BoardEntry.from_recents.accessible(current_user).entry_type_is(BoardEntry::GROUP_BBS).timeline.scoped(:include => [ :user, :state ]).order_new.paginate(:page => target_page(id_name), :per_page => options[:per_page])

    locals = {
      :id_name => id_name,
      :title_icon => "group",
      :title_name => category.name,
      :per_page => options[:per_page],
      :pages => pages
    }
  end

  def recent_bbs
    recent_bbs = []
    gid_by_category = Group.gid_by_category
    GroupCategory.ascend_by_sort_order.each do |category|
      options = { :group_symbols => gid_by_category[category.id], :per_page => per_page }
      recent_bbs << find_recent_bbs_as_locals(category.code.downcase, options)
    end
    recent_bbs
  end

  def unifed_feeds
    returning [] do |feeds|
      Admin::Setting.mypage_feed_settings(current_tenant).each do |setting|
        feed = nil
        timeout(Admin::Setting.mypage_feed_timeout(current_tenant).to_i) do
          feed = open(setting[:url], :proxy => GlobalInitialSetting['proxy_url']) do |f|
            FeedNormalizer::FeedNormalizer.parse(f.read)
          end
        end
        feed.title = setting[:title] if setting[:title]
        limit = (setting[:limit] || Admin::Setting.mypage_feed_default_limit(current_tenant))
        feed.items.slice!(limit..-1) if feed.items.size > limit
        feeds << feed
      end
    end
  end

  def valid_list_types
    %w(questions access_blogs recent_blogs) | GroupCategory.all.map{ |gc| gc.code.downcase }
  end

  # TODO helperへ移動する
  # アンテナの記事一覧のタイトル
  def antenna_entry_title(antenna_entry)
    if antenna = antenna_entry.antenna
      antenna.name
    else
      key = antenna_entry.key
      case
      when key == 'message'  then _("Notices for you")
      when key == 'comment'  then _("Entries you have made comments")
      when key == 'joined_group'    then _("Posts in the groups joined")
      else
        _('List of unread entries')
      end
    end
  end

  # TODO UserReadingに移動する
  # TODO SystemAntennaEntry等の記事取得の際に一緒に取得するようなロジックに出来ないか?
  #   => target_typeの判定ロジックが複数箇所に現れるのをなくしたい
  # 指定した記事idのをキーとした未読状態のUserReadingのハッシュを取得
  def unread_entry_id_hash_with_user_reading(entry_ids, target_type)
    result = {}
    if entry_ids && entry_ids.size > 0
      user_readings_conditions =
        # readがmysqlの予約語なのでバッククォートで括らないとエラー
        if target_type == 'message'
          ["user_id = ? AND board_entry_id in (?) AND `read` = ? AND notice_type = ?", current_user.id, entry_ids, false, 'notice']
        else
          ["user_id = ? AND board_entry_id in (?) AND `read` = ?", current_user.id, entry_ids, false]
        end
      user_readings = UserReading.find(:all, :conditions => user_readings_conditions)
      user_readings.map { |user_reading| result[user_reading.board_entry_id] = user_reading }
    end
    result
  end

  # TODO mypageのcontroller及びviewで@userを使うのをやめてcurrent_target_userにしてなくしたい。
  def load_user
    @user = current_user
  end

  def current_target_user
    current_user
  end

  def target_page target = nil
    if target
      target_key2current_pages = cookies[:target_key2current_pages]
      if target_key2current_pages.blank?
        params[:page]
      else
        params[:page] || JSON.parse(target_key2current_pages)[target] || 1
      end
    else
      params[:page]
    end
  end

  def save_current_page_to_cookie
    if params[:target] && params[:page]
      target_key2current_pages =
        begin
          JSON.parse(cookies[:target_key2current_pages])
        rescue => e
          {}
        end
      target_key2current_pages[params[:target]] = params[:page]
      cookies[:target_key2current_pages] = { :value => target_key2current_pages.to_json, :expires => 30.days.from_now }
      true
    else
      false
    end
  end
end
