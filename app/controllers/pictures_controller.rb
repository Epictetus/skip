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

class PicturesController < ApplicationController
  before_filter :target_user_required, :only => %w(show)
  skip_before_filter :login_required, :only => :show
  before_filter :only => :show do |c|
    c.send(:login_required, {:trace_access => false})
  end

  def show
    @picture = current_target_user.pictures.find(params[:id])
    if stale?(:etag => @picture, :last_modified => @picture.updated_on)
      send_data(@picture.data, :filename => @picture.name, :type => @picture.content_type, :disposition => "inline")
    end
  end

  def create
    pictures = current_user.pictures
    picture = pictures.build(params[:picture])
    picture.active = true if pictures.size == 1
    respond_to do |format|
      if picture.save
        flash[:notice] = _("Picture was updated successfully.")
      else
        flash[:warn] = picture.errors.full_messages
      end
      format.html { redirect_to new_tenant_user_picture_url(current_tenant, current_user) }
    end
  end

  def update
    picture = current_user.pictures.find(params[:id])
    picture.activate!
    respond_to do |format|
      format.html do
        flash[:notice] = _("Picture was updated successfully.")
        redirect_to new_tenant_user_picture_url(current_tenant, current_user)
      end
    end
  end

  def destroy
    picture = current_user.pictures.find(params[:id])
    respond_to do |format|
      unless picture
        flash[:warn] = _('Picture could not be deleted since it does not found.')
      else
        if Admin::Setting.enable_change_picture(current_tenant)
          picture.destroy
          flash[:notice] = _("Picture was deleted successfully.")
        else
          flash[:warn] = _("Picture could not be changed.")
        end
      end
      format.html { redirect_to new_tenant_user_picture_url(current_tenant, current_user) }
    end
  end
end
