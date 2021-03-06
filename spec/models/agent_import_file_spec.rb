# -*- encoding: utf-8 -*-
require 'spec_helper'

describe AgentImportFile do
  fixtures :all

  let(:examples_path) { EnjuTrunk::Engine.root + 'examples' }

  describe "when its mode is 'create'" do
    before(:each) do
      @file = AgentImportFile.create! :agent_import => File.new("#{examples_path}/agent_import_file_sample1.tsv")
    end

    it "should be imported" do
      old_agents_count = Agent.count
      old_import_results_count = AgentImportResult.count
      @file.state.should eq 'pending'
      @file.import_start.should eq({:agent_imported => 3, :user_imported => 2, :failed => 0})
      Agent.order('id DESC')[0].full_name.should eq '原田 ushi 隆史'
      Agent.order('id DESC')[1].full_name.should eq '田辺浩介'
      Agent.order('id DESC')[2].date_of_birth.should eq Time.zone.parse('1978-01-01')
      Agent.count.should eq old_agents_count + 3
      AgentImportResult.count.should eq old_import_results_count + 4
    end
  end

  describe "when it is written in shift_jis" do
    before(:each) do
      @file = AgentImportFile.create! :agent_import => File.new("#{examples_path}/agent_import_file_sample3.tsv")
    end

    it "should be imported" do
      old_agents_count = Agent.count
      old_import_results_count = AgentImportResult.count
      @file.state.should eq 'pending'
      @file.import_start.should eq({:agent_imported => 4, :user_imported => 2, :failed => 0})
      Agent.count.should eq old_agents_count + 4
      Agent.order('id DESC')[0].full_name.should eq '原田 ushi 隆史'
      Agent.order('id DESC')[1].full_name.should eq '田辺浩介'
      Agent.order('id DESC')[2].email.should eq 'fugafuga@example.jp'
      Agent.order('id DESC')[3].required_role.should eq Role.find_by_name('Guest')
      Agent.order('id DESC')[1].email.should be_nil
      AgentImportResult.count.should eq old_import_results_count + 5
    end
  end

  describe "when its mode is 'update'" do
    it "should update users" do
      @file = AgentImportFile.create :agent_import => File.new("#{examples_path}/user_update_file.tsv")
      @file.modify
      User.where(:user_number => '00001').first.username.should eq 'user11'
      User.where(:user_number => '00001').first.agent.full_name.should eq 'たなべこうすけ'
      User.where(:user_number => '00001').first.agent.address_1.should eq '東京都'
      User.where(:user_number => '00002').first.username.should eq 'user12'
      User.where(:user_number => '00002').first.agent.address_1.should eq '東京都'
      User.where(:user_number => '00003').first.username.should eq 'user13'
    end
  end

  describe "when its mode is 'destroy'" do
    it "should remove users" do
      old_count = User.count
      @file = AgentImportFile.create :agent_import => File.new("#{examples_path}/user_delete_file.tsv")
      @file.remove
      User.count.should eq old_count - 3
    end
  end
end

# == Schema Information
#
# Table name: agent_import_files
#
#  id                         :integer         not null, primary key
#  parent_id                  :integer
#  content_type               :string(255)
#  size                       :integer
#  file_hash                  :string(255)
#  user_id                    :integer
#  note                       :text
#  imported_at                :datetime
#  state                      :string(255)
#  agent_import_file_name    :string(255)
#  agent_import_content_type :string(255)
#  agent_import_file_size    :integer
#  agent_import_updated_at   :datetime
#  created_at                 :datetime
#  updated_at                 :datetime
#  edit_mode                  :string(255)
#

