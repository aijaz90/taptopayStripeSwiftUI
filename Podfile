# Podfile for MyTon
# Stripe Terminal (Tap to Pay on iPhone) + Stripe payments SDK.

platform :ios, '16.0'

target 'MyTon' do
  use_frameworks!

  # Tap to Pay on iPhone / card readers.
  pod 'StripeTerminal', '~> 4.0'

  # General Stripe payments SDK (PaymentIntents, PaymentSheet, etc.).
  pod 'StripePaymentSheet', '~> 24.0'
  pod 'Stripe', '~> 24.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end
