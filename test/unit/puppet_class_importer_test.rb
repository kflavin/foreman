require 'test_helper'

class PuppetClassImporterTest < ActiveSupport::TestCase
  def setup
    ProxyAPI::Puppet.any_instance.stubs(:environments).returns(["foreman-testing","foreman-testing-1"])
    ProxyAPI::Puppet.any_instance.stubs(:classes).returns(mocked_classes)
  end

  test "should support providing proxy" do
    proxy = smart_proxies(:puppetmaster)
    klass = PuppetClassImporter.new(:proxy => ProxyAPI::Puppet.new(:url => proxy.url))
    assert_kind_of ProxyAPI::Puppet, klass.send(:proxy)
  end

  test "should support providing url" do
    proxy = smart_proxies(:puppetmaster)
    klass = PuppetClassImporter.new(:url => proxy.url)
    assert_kind_of ProxyAPI::Puppet, klass.send(:proxy)
  end

  test "should contain only the specified environment in changes" do
    proxy = smart_proxies(:puppetmaster)
    importer = PuppetClassImporter.new(:url => proxy.url, :env => 'foreman-testing')
    assert importer.changes['new'].include?('foreman-testing')
    assert !importer.changes['new'].include?('foreman-testing-1')
  end

  test "should return list of envs" do
    assert_kind_of Array, get_an_instance.db_environments
  end

  test "should return list of actual puppet envs" do
    assert_kind_of Array, get_an_instance.actual_environments
  end

  test "should return list of classes" do
    importer = get_an_instance
    assert_kind_of ActiveRecord::Relation, importer.db_classes(importer.db_environments.first)
  end

  test "should return list of actual puppet classes" do
    importer = get_an_instance
    assert_kind_of Hash, importer.actual_classes(importer.actual_environments.first)
  end

  test "should obey config/ignored_environments.yml" do
    as_admin do
      hostgroups(:inherited).destroy #needs to be deleted first, since it has ancestry
      Hostgroup.destroy_all #to satisfy FK contraints when deleting Environments
      Environment.destroy_all
    end

    importer = get_an_instance
    importer.stubs(:ignored_environments).returns(["foreman-testing"])
    assert !importer.actual_environments.include?("foreman-testing")
  end

  context '#update_classes_in_foreman removes parameters' do
    setup do
      @envs = FactoryGirl.create_list(:environment, 2)
      @pc = FactoryGirl.create(:puppetclass, :environments => @envs)
    end

    test 'from one environment' do
      lks = FactoryGirl.create_list(:puppetclass_lookup_key, 2, :as_smart_class_param, :puppetclass => @pc)
      get_an_instance.send(:update_classes_in_foreman, @envs.first.name,
                           {@pc.name => {'obsolete' => [lks.first.key]}})
      assert_equal [@envs.last], lks.first.environments
      assert_equal @envs, lks.last.environments
    end

    test 'when overridden' do
      lks = FactoryGirl.create_list(:puppetclass_lookup_key, 2, :as_smart_class_param, :with_override, :puppetclass => @pc)
      get_an_instance.send(:update_classes_in_foreman, @envs.first.name,
                           {@pc.name => {'obsolete' => [lks.first.key]}})
      assert_equal [@envs.last], lks.first.environments
      assert_equal @envs, lks.last.environments
    end

    test 'deletes the key from all environments' do
      lks = FactoryGirl.create_list(:puppetclass_lookup_key, 2, :as_smart_class_param, :with_override, :puppetclass => @pc)
      lval = lks.first.lookup_values.first
      get_an_instance.send(:update_classes_in_foreman, @envs.first.name,
                           {@pc.name => {'obsolete' => [lks.first.key]}})
      get_an_instance.send(:update_classes_in_foreman, @envs.last.name,
                           {@pc.name => {'obsolete' => [lks.first.key]}})
      refute PuppetclassLookupKey.find_by_id(lks.first.id)
      refute LookupValue.find_by_id(lval.id)
      assert_equal @envs, lks.last.environments
    end
  end

  private

  def get_an_instance
    PuppetClassImporter.new :url => smart_proxies(:puppetmaster).url
  end

  def mocked_classes
    pcs = [{
      "apache::service" => {
        "name"   => "service",
        "params" => { "port" => "80", "version" => "2.0" },
        "module" => "apache"
      }
    }]
    Hash[pcs.map { |k| [k.keys.first, Foreman::ImporterPuppetclass.new(k.values.first)] }]
  end
end
