require "spec_helper"

describe OrganizationLicenseAudit do
  it "has a VERSION" do
    OrganizationLicenseAudit::VERSION.should =~ /^[\.\da-z]+$/
  end
end
