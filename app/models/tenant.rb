class Tenant < ActiveRecord::Base
  has_many :users, :dependent => :destroy
  has_many :board_entries, :dependent => :destroy
  has_many :share_files, :dependent => :destroy
  has_many :groups, :dependent => :destroy
  has_many :group_categories, :dependent => :destroy
  has_one :activation, :dependent => :destroy
  has_many :user_profile_master_categories, :dependent => :destroy
  has_many :user_profile_masters, :dependent => :destroy
  has_many :site_counts, :dependent => :destroy

  serialize :initial_settings
end
