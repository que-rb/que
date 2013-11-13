shared_examples "a database connection" do
  it "should be able to drop and create the jobs table" do
    DB.table_exists?(:que_jobs).should be true
    Que.drop!
    DB.table_exists?(:que_jobs).should be false
    Que.create!
    DB.table_exists?(:que_jobs).should be true
  end

  it "should be able to clear the jobs table" do
    DB[:que_jobs].insert :type => "Que::Job"
    DB[:que_jobs].count.should be 1
    Que.clear!
    DB[:que_jobs].count.should be 0
  end
end
