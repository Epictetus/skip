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

class UserMailer::Base < ActionMailer::Base
  helper :initial_settings
  helper :user_mailer

  default_url_options[:host] = GlobalInitialSetting['host_and_port']
  default_url_options[:protocol] = GlobalInitialSetting['protocol']

private
  def self.base64(text)
    if GetText.locale.language == 'ja'
      NKF.nkf("-WMm0 --oc=ISO-2022-JP-1", text)
    else
      text
    end
  end

  def site_url tenant
    default_url_options[:protocol] + default_url_options[:host] + "tenant/#{tenant.id}"
  end

  def contact_addr tenant
    Admin::Setting.contact_addr(tenant)
  end

  def from tenant
    self.class.base64(Admin::Setting.abbr_app_title(tenant)) + "<#{contact_addr(tenant)}>"
  end

  def header
  end

  def footer tenant
    noreply_description = _('*This email is automatically delivered from the system. Please do not reply.')
    contact_description = _('For questions regarding this email, please contact:') % {:sender => sender}
    "----\n#{noreply_description}\n\n" +
    "*#{contact_description}\n#{contact_addr(tenant)}\n\n*#{sender(tenant)}\n#{site_url(tenant)}"
  end

  def sender tenant
    ERB::Util.html_escape(Admin::Setting.abbr_app_title(tenant))
  end

  def smtp_settings
    GlobalInitialSetting['mail']['smtp_settings']
  end
end
