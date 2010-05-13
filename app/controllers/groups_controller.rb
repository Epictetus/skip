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

class GroupsController < ApplicationController
  include AccessibleGroup
  before_filter :setup_layout, :except => %w(new create)
  before_filter :target_group_required => %w(show update destroy members)
  before_filter :required_full_accessible_group, :only => %w(update destroy)
  after_filter :remove_system_message, :only => %w(show members)

  def index
    search_params = params[:search] || {}
    search_params[:group_category_id_is] ||= 'all'
    @search =
      if current_target_user
        current_target_user.groups.order_active
      else
        if search_params[:unjoin]
          search_params[:unjoin] = search_params[:unjoin] == 'false' ?  nil : current_user.id
        end
        Group.tenant_id_is(current_tenant.id).order_active
      end
    @search = @search.search(search_params)
    # paginteの検索条件にgroup byが含まれる場合、countでgroup by が考慮されないので
    @groups = @search.paginate(:count => {:select => 'distinct(groups.id)'}, :page => params[:page], :per_page => 50)
    flash.now[:notice] = _('No matching groups found.') if @groups.empty?
    respond_to do |format|
      format.html do
        flash.now[:notice] = _('No matching groups found.') if @groups.empty?
        render
      end
    end
  end

  def show
    @group = current_target_group
    @owners = User.owned(current_target_group).order_joined.limit(20)
    @except_owners = User.joined_except_owned(current_target_group).order_joined.limit(20)
    @recent_messages = BoardEntry.owned(current_target_group).accessible(current_user).scoped(:include => [ :user, :state ]).order_sort_type("date").all(:limit => 10)
  end

  def new
    @main_menu = @title = _('Create a new group')
    @group = current_tenant.groups.build(:default_publication_type => 'public')
    if category = current_tenant.group_categories.first
      @group.group_category_id = category.id
    end
  end

  def create
    @main_menu = @title = _('Create a new group')
    @group = current_tenant.groups.build(params[:group])
    @group.group_participations.build(:user_id => current_user.id, :owned => true)

    if @group.save
      current_user.notices.create(:target => @group)
      @group.create_index
      flash[:notice] = _('Group was created successfully.')
      redirect_to [current_tenant, @group]
    else
      render :action => 'new'
    end
  end

  def edit
    @group = current_target_group
  end

  def update
    @group = current_target_group
    if @group.update_attributes(params[:group])
      @group.update_index
      flash[:notice] = _('Group information was successfully updated.')
      redirect_to [current_tenant, @group]
    else
      render :edit
    end
  end

  def destroy
    @group = current_target_group
    if @group.group_participations.size > 1
      flash[:warn] = _('Failed to delete since there are still other users in the group.')
      redirect_to [current_tenant, @group]
    else
      @group.destroy
      @group.destroy_index
      flash[:notice] = _('Group was successfully deleted.')
      redirect_to tenant_groups_url(current_tenant)
    end
  end

  def members
    @users = current_target_group.users.paginate(:page => params[:page])

    flash.now[:notice] = _('User not found.') if @users.empty?
  end

private
  def setup_layout
    @main_menu = @title = _('Groups')
  end
end
