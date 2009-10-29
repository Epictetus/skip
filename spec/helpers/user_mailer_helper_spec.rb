# SKIP(Social Knowledge & Innovation Platform)
# Copyright (C) 2008-2009 TIS Inc.
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

require File.dirname(__FILE__) + '/../spec_helper'

describe UserMailerHelper, '#convert_plain' do
  describe '100文字未満のタグが含まれない本文の場合' do
    before do
      @entry = create_board_entry :contents => 'テスト'
    end
    it '本文がそのまま取得出来ること' do
      helper.convert_plain(@entry).should == "#{space}テスト\n#{space}\n"
    end
  end
  describe '100文字を越えるタグが含まれない本文の場合' do
    before do
      @entry = create_board_entry :contents => 'あ'*101
    end
    it '本文が100文字で切断されていること' do
      helper.convert_plain(@entry).should == "#{space}#{'あ'*100}"
    end
  end
  describe '改行が含まれる本文の場合' do
    before do
      @entry = create_board_entry :contents => "\r\n\r\n\tこれは本文です。\r\n\r\n\t", :editor_mode => "richtext"
    end
    it "改行により本文が空にならないこと" do
      helper.convert_plain(@entry).should == "#{space}\r\n#{space}\r\n#{space}これは本文です。\r\n#{space}\r\n"
    end
  end
  describe '&nbspが表示されないこと' do
    before do
      @entry = create_board_entry :contents => "&nbsp;これは本文です。", :editor_mode => "richtext"
    end
    it "改行により本文が空にならないこと" do
      helper.convert_plain(@entry).should == "#{space} これは本文です。"
    end
  end
  describe 'pタグやbrタグが含まれる場合' do
    before do
      @entry = create_board_entry :contents => "<p>1行目です。<br />2行目です。<br>3行目です。</p>", :editor_mode => "richtext"
    end
    it 'pタグやbrが改行に変換されていること' do
      helper.convert_plain(@entry).should == "#{space}1行目です。\n#{space}2行目です。\n#{space}3行目です。\n"
    end
  end
  # 各行の先頭に開けられるspace
  def space
    ' '*4
  end
end
