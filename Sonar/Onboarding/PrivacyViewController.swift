//
//  PrivacyViewController.swift
//  Sonar
//
//  Created by NHSX on 3/31/20.
//  Copyright © 2020 NHSX. All rights reserved.
//

import UIKit

class PrivacyViewController: UIViewController, Storyboarded
{
    static let storyboardName = "Onboarding"

    private var continueHandler: (() -> Void)!

    @IBOutlet var moreAbout: LinkButton!
    @IBOutlet var privacyPolicy: LinkButton!
    @IBOutlet var termsConditions: LinkButton!

    override func viewDidLoad()
    {
        moreAbout.inject(title: "More about the app".localized, external: true, style: .body)
        privacyPolicy.inject(title: "Privacy notice".localized, external: true, style: .body)
        termsConditions.inject(title: "Terms of use".localized, external: true, style: .body)
    }

    func inject(continueHandler: @escaping () -> Void)
    {
        self.continueHandler = continueHandler
    }

    @IBAction func tapMoreAbout(_: Any)
    {
        UIApplication.shared.open(URL(string: "https://covid19.nhs.uk")!)
    }

    @IBAction func tapPrivacy(_: Any)
    {
        UIApplication.shared.open(URL(string: "https://covid19.nhs.uk/privacy-and-data.html")!)
    }

    @IBAction func tapTerms(_: Any)
    {
        UIApplication.shared.open(URL(string: "https://covid19.nhs.uk/our-policies.html")!)
    }

    @IBAction func didTapClose(_: Any)
    {
        presentingViewController?.dismiss(animated: true)
    }
}
