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

class Admin::UsersController < Admin::ApplicationController
  include Admin::AdminModule::AdminRootModule

  verify :method => :post, :only => %w(lock_actives reset_all_password_expiration_periods)

  skip_before_filter :sso, :only => [:first]
  skip_before_filter :login_required, :only => [:first]
  skip_before_filter :prepare_session, :only => [:first]
  skip_before_filter :require_admin, :only => [:first]
  skip_before_filter :valid_tenant_required, :only => [:first]

  def new
    @user = Admin::User.new
    @topics = [[_('Listing %{model}') % {:model => _('user')}, admin_tenant_users_path(current_tenant)], _('New %{model}') % {:model => _('user')}]
  end

  def create
    begin
      Admin::User.transaction do
        if login_mode?(:fixed_rp)
          @user = User.create_with_identity_url(params[:openid_identifier][:url],
                                                  :name => params[:user][:name],
                                                  :email => params[:user][:email])
          @user.save!
        else
          @user = Admin::User.make_new_user({:user => params[:user]})
          @user.tenant = current_tenant
          @user.save!
        end
      end

      flash[:notice] = _('Registered.')
      redirect_to admin_tenant_users_path(current_tenant)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      @topics = [[_('Listing %{model}') % {:model => _('user')}, admin_tenant_users_path(current_tenant)], _('New %{model}') % {:model => _('user')}]
      render :action => 'new'
    end
  end

  def edit
    @user = Admin::User.tenant_id_is(current_tenant.id).find(params[:id])

    @topics = [[_('Listing %{model}') % {:model => _('user')}, admin_tenant_users_path(current_tenant)],
               _('Editing %{model}') % {:model => @user.topic_title }]
  rescue ActiveRecord::RecordNotFound => e
    flash[:notice] = _('User does not exist.')
    redirect_to admin_tenant_users_path(current_tenant)
  end

  def update
    @user = Admin::User.make_user_by_id(params)
    if @user.id == current_user.id and (@user.status != current_user.status or @user.admin != current_user.admin or @user.locked != current_user.locked)
      @user.status = current_user.status
      @user.admin = current_user.admin
      @user.locked = current_user.locked
      @user.errors.add_to_base(_('Admins are not allowed to change their own status, admin and lock rights. Log in with another admin account to do so.'))
      raise ActiveRecord::RecordInvalid.new(@user)
    end
    @user.trial_num = 0 unless @user.locked
    @user.save!
    flash[:notice] = _('Updated.')
    redirect_to :action => "edit"
  rescue ActiveRecord::RecordNotFound => e
    flash[:notice] = _('User does not exist.')
    redirect_to admin_tenant_users_path(current_tenant)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    @topics = [[_('Listing %{model}') % {:model => _('user')}, admin_tenant_users_path(current_tenant)],
               _('Editing %{model}') % {:model => @user.topic_title }]
    render :action => 'edit'
  end

  def destroy
    @user = Admin::User.tenant_id_is(current_tenant.id).find(params[:id])
    if @user.unused?
      @user.destroy
      flash[:notice] = _('User was successfuly deleted.')
    else
      flash[:notice] = _("You cannot delete user who is not unused.")
    end
    redirect_to admin_tenant_users_path(current_tenant)
  end

  def first
    required_activation_code do
      if request.get?
        @user = Admin::User.new
        render :layout => 'not_logged_in'
      else
        begin
          Admin::User.transaction do
            @user = Admin::User.make_user({:user => params[:user].merge(:tenant_id => current_tenant.id)}, true)
            @user.user_access = UserAccess.new :last_access => Time.now, :access_count => 0
            @user.save!
            current_activation.update_attributes(:code => nil)
          end
          flash[:notice] = _('Registered.') + _('Log in again.')
          redirect_to [current_tenant, :platform]
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
          render :layout => 'not_logged_in'
        end
      end
    end
  end

  def import_confirmation
    @topics = [[_('Listing %{model}') % {:model => _('user')}, admin_users_path], _('New users from CSV')]
    if request.get? || !valid_file?(params[:file], :content_types => ['text/csv', 'application/x-csv', 'application/vnd.ms-excel', 'text/plain'])
      @users = []
      return render(:action => :import)
    end
    @users = Admin::User.make_users(params[:file], params[:options], params[:update_registered].blank?)
    import!(@users)
    flash.now[:notice] = _('Verified content of CSV file.')
    render :action => :import
  rescue ActiveRecord::RecordInvalid,
         ActiveRecord::RecordNotSaved => e
    @users.each {|user| user.valid?}
    flash.now[:notice] = _('Verified content of CSV file.')
    render :action => :import
  end

  def import
    @topics = [[_('Listing %{model}') % {:model => _('user')}, admin_users_path], _('New users from CSV')]
    @error_row_only = true
    if request.get? || !valid_file?(params[:file], :content_types => ['text/csv', 'application/x-csv', 'application/vnd.ms-excel', 'text/plain'])
      @users = []
      return
    end
    @users = Admin::User.make_users(params[:file], params[:options], params[:update_registered].blank?)
    import!(@users, false)
    flash[:notice] = _('Successfully added/updated users from CSV file.')
    redirect_to admin_users_path
  rescue ActiveRecord::RecordInvalid,
         ActiveRecord::RecordNotSaved => e
    @users.each {|user| user.valid?}
    flash.now[:error] = _('Illegal value(s) found in CSV file.')
  end

  def issue_activation_code
    do_issue_activation_codes([params[:id]])
    redirect_to admin_tenant_users_path(current_tenant)
  end

  def issue_activation_codes
    do_issue_activation_codes params[:ids]
    redirect_to admin_users_path
  end

  def issue_password_reset_code
    @user = Admin::User.tenant_id_is(current_tenant.id).find(params[:id])
    if @user.active?
      if @user.reset_auth_token.nil? || !@user.within_time_limit_of_reset_auth_token?
        @user.issue_reset_auth_token
        @user.save_without_validation!
      end
      @reset_password_url = reset_password_url(@user.reset_auth_token)
      @mail_body = render_to_string(:template => "user_mailer/smtp/sent_forgot_password", :layout => false)
      render :layout => false
    else
      flash[:error] = _('Password resetting code cannot be issued for unactivated users.')
      redirect_to edit_admin_user_path(params[:id])
    end
  end

  def lock_actives
    flash[:notice] = _('Updated %{count} records.')%{:count => Admin::User.lock_actives}
    redirect_to admin_settings_path(:tab => :security)
  end

  def reset_all_password_expiration_periods
    flash[:notice] = _('Updated %{count} records.')%{:count => Admin::User.reset_all_password_expiration_periods(current_tenant)}
    redirect_to admin_settings_path(:tab => :security)
  end

  private
  def required_activation_code
    if result = params[:code] && current_activation
      yield if block_given?
    else
      contact_link = "<a href=\"mailto:#{GlobalInitialSetting['administrator_addr']}\" target=\"_blank\">" + _('Inquiries') + '</a>'
      if User.tenant_id_is(current_tenant.id).find_by_admin(true)
        flash[:error] = _('Administrative user has already been registered. Log in with the account or contact {contact_link} in case of failure.') % {:contact_link => contact_link}
        redirect_to :controller => "/platform", :action => :index
      else
        flash.now[:error] = _('Operation unauthorized. Verify the URL and retry. Contact %{contact_link} if the problem persists.') % {:contact_link => contact_link}
        render :text => '', :status => :forbidden, :layout => 'not_logged_in'
      end
    end
    result
  end

  def current_activation
    @activation ||= Activation.find_by_code(params[:code])
  end

  def import!(users, rollback = true)
    Admin::User.transaction do
      users.each do |user|
        user.save!
      end
      raise ActiveRecord::Rollback if rollback
    end
  end

  def do_issue_activation_codes user_ids
    User.issue_activation_codes(current_tenant, user_ids) do |unused_users, active_users|
      unused_users.each do |unused_user|
        UserMailer::Smtp.deliver_sent_activate(current_tenant, unused_user.email, unused_user, signup_tenant_platform_url(current_tenant, :code => unused_user.activation_token))
      end
      unless unused_users.empty?
        email = unused_users.map(&:email).join(',')
        flash[:notice] =
          if GlobalInitialSetting['mail']['show_mail_function']
            n_("An email containing the URL for signup will be sent to %{email}.", "%{num} emails containing the URL for signup will be sent to the following email address. %{email}", unused_users.size) % {:num => unused_users.size, :email => email}
          else
            n_("The URL for signup issued. Please contact a use from comfirm link", "The URLs for signup issued. Please contact some users from comfirm link", unused_users.size)
          end
      end

      unless active_users.empty?
        flash[:error] = n_("Email address %{email} has been registered in the site", "%{num} emails have been registered in the site", active_users.size) % {:num => active_users.size, :email => active_users.map(&:email).join(',')}
      end
    end
  end
end
