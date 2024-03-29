public class VAT_checkVat {

    public static Boolean triggerFutureClass;
    public static Set<String> euCountryCodes = new Set<String>{
        'AT', // Austria
        'BE', // Belgium
        'CY', // Cyprus
        'CZ', // Czech Republic
        'DE', // Germany
        'DK', // Denmark
        'EE', // Estonia
        'GR', // Greece
        'ES', // Spain
        'FI', // Finland
        'FR', // France
        'HR', // Croatia
        'HU', // Hungary
        'IE', // Ireland --> Should only be Northen-Ireland but this option is not available in SalesForce
        'IT', // Italy
        'LT', // Lithuania
        'LU', // Luxembourg
        'LV', // Latvia
        'MT', // Malta
        'NL', // Netherlands
        'PL', // Poland
        'PT', // Portugal
        'RO', // Romania
        'SE', // Sweden
        'SI', // Slovenia
        'SK', // Slovakia
        'IE' // Ireland
    };
    
    public static void CheckVatOnUpdate(Map<Id, Account> accountMap, Map<Id, Account> oldMap) {
        System.debug('VAT_checkVat - CheckVatOnUpdate - start');

        Boolean doQuery = false;
        Map<Id,Map<String,String>> accountMapForCallout = new Map<Id,Map<String,String>>();
        List<Account> accountUpdateList = new List<Account>();

        // #################### NEW
        List<String> vatNrList = new List<String>();
        for (Account acc : accountMap.values()) {
            System.debug('acc.VATNumber__c ==> ' + acc.VATNumber__c);
            if (acc.VATNumber__c != null && acc.VATNumber__c != oldMap.get(acc.Id).VATNumber__c && acc.VATNumber__c != '' && acc.VATNumber__c != '0') {
                doQuery = true;
                vatNrList.add(acc.VATNumber__c);
            }
        }
        
        Map<String,Account> vatNumberAccountMap = new Map<String,Account>();
        List<Account> currentVATAccountList = new List<Account>();
        if (doQuery) {
            currentVATAccountList = [SELECT VATNumber__c, VATStatus__c FROM Account WHERE VATNumber__c IN :vatNrList];
        }
        for (Account acc : currentVATAccountList) {
            vatNumberAccountMap.put(acc.VATNumber__c.replace('.', '').replace(' ', '').replace('-', ''),acc);
        }
        // #################### END OF NEW

        for (Account acc : accountMap.values()) {

            if (acc.VATNumber__c != oldMap.get(acc.Id).VATNumber__c) {
                Account newAcc = new Account();
                newAcc.Id = acc.Id;
                if (acc.VATNumber__c == null || acc.VATNumber__c == '') {
                    // If we do not have a VAT number set VAT Status to NA
                    newAcc.VATStatus__c = 'NA';
                } else {

                    String cleanVATnr = acc.VATNumber__c.replace('.', '').replace(' ', '').replace('-', '');
                    if (vatNumberAccountMap.containsKey(cleanVATnr) && acc.Id != vatNumberAccountMap.get(cleanVATnr).Id) {
                        String vatStatus = vatNumberAccountMap.get(cleanVATnr).VATStatus__c;
                        System.debug('VATNumber already known, Status: ' + vatStatus);
                        newAcc.VATStatus__c = vatStatus;
                    } else if (!euCountryCodes.contains(acc.BillingCountryCode)) {
                        // If country is not within EU
                        newAcc.VATStatus__c = 'Manual verification required';
                        newAcc.VATErrorMessage__c = '!!!! WE CANNOT VERIFY THIS VAT NUMBER !!!! The Billing country is not a member of the EU. Manual verification is required';
                    } else {
                        Map<String,String> tempMap = new Map<String,String>();
                        // get Vat info from Account and store in temporary Map
                        String countryCode = acc.BillingCountryCode;
                        String vatNumber = acc.VATNumber__c;
                        tempMap.put('countryCode',acc.BillingCountryCode);
                        tempMap.put('vatNumber',acc.VATNumber__c);

                        // create Map for callouts
                        accountMapForCallout.put(acc.Id,tempMap);

                        // Set temp status to processing (will be overwritten when the correct status is received from the VIES callout)
                        newAcc.VATStatus__c = 'Processing';
                        newAcc.VATErrorMessage__c = '';
                    }
                }
                accountUpdateList.add(newAcc);
            }
        }

        if (accountUpdateList.size() > 0) {
            update accountUpdateList;
        }

        if (accountMapForCallout.keySet().size() > 0) {

            List<String> paramList = new List<String>();

            for (Id accountId : accountMapForCallout.keySet()) {

                String param = String.ValueOf(accountId) + ';' + accountMapForCallout.get(accountId).get('countryCode') + ';' + accountMapForCallout.get(accountId).get('vatNumber');

                if (triggerFutureClass == null) {
                    
                    // Call @future method to get VIES Check of VAT number
                    paramList.add(param);
                }
            }
            VAT_ViesCallout.MakeCallout(paramList);
        }

        System.debug('VAT_checkVat - CheckVatOnUpdate - end');
    }

    public static void CheckVatOnInsert(List<Account> accounts) {
        System.debug('VAT_checkVat - CheckVatOnInsert - start');

        Boolean doQuery = false;
        Map<Id,Map<String,String>> accountMapForCallout = new Map<Id,Map<String,String>>();
        List<Account> accountUpdateList = new List<Account>();

        List<String> vatNrList = new List<String>();
        for (Account acc : accounts) {
            if (acc.VATNumber__c != null && acc.VATNumber__c != '' && acc.VATNumber__c != '0') {
                doQuery = true;
                vatNrList.add(acc.VATNumber__c);
            }
        }

        // #################### NEW
        Map<String,Account> vatNumberAccountMap = new Map<String,Account>();
        List<Account> currentVATAccountList = new List<Account>();
        if (doQuery) {
            currentVATAccountList = [SELECT VATNumber__c, VATStatus__c FROM Account WHERE VATNumber__c IN : vatNrList];
        }
        for (Account acc : currentVATAccountList) {
            vatNumberAccountMap.put(acc.VATNumber__c.replace('.', '').replace(' ', '').replace('-', ''),acc);
        }
        // #################### END OF NEW

        for (Account acc : accounts) {

            Account newAcc = new Account();
            newAcc.Id = acc.Id;

            // if VAT number is not empty update the VAT number Status
            if (acc.VATNumber__c != null && acc.VATNumber__c != '') {

                String cleanVATnr = acc.VATNumber__c.replace('.', '').replace(' ', '').replace('-', '');
                if (vatNumberAccountMap.containsKey(cleanVATnr) && acc.Id != vatNumberAccountMap.get(cleanVATnr).Id) {
                    String vatStatus = vatNumberAccountMap.get(cleanVATnr).VATStatus__c;
                    System.debug('VATNumber already known, Status: ' + vatStatus);
                    newAcc.VATStatus__c = vatStatus;
                } else if (!euCountryCodes.contains(acc.BillingCountryCode)) {
                    // If country is not within EU
                    newAcc.VATStatus__c = 'Manual verification required';
                    newAcc.VATErrorMessage__c = '!!!! WE CANNOT VERIFY THIS VAT NUMBER !!!! The Billing country is not a member of the EU. Manual verification is required';
                } else {
                    Map<String,String> tempMap = new Map<String,String>();
                    // get Vat info from Account and store in temporary Map
                    String countryCode = acc.BillingCountryCode;
                    String vatNumber = acc.VATNumber__c;
                    tempMap.put('countryCode',acc.BillingCountryCode);
                    tempMap.put('vatNumber',acc.VATNumber__c);

                    // create Map for callouts
                    accountMapForCallout.put(acc.Id,tempMap);
                    
                    // Set temp status to processing (will be overwritten when the correct status is received from the VIES callout)
                    newAcc.VATStatus__c = 'Processing';
                    newAcc.VATErrorMessage__c = '';
                }
                
            } else {
                // If we do not have a VAT number set VAT Status to NA
                newAcc.Id = acc.Id;
                newAcc.VATStatus__c = 'NA';
            }
            accountUpdateList.add(newAcc);
        }

        if (accountUpdateList.size() > 0) {
            update accountUpdateList;
        }

        if (accountMapForCallout.keySet().size() > 0) {

            List<String> paramList = new List<String>();

            for (Id accountId : accountMapForCallout.keySet()) {

                String param = String.ValueOf(accountId) + ';' + accountMapForCallout.get(accountId).get('countryCode') + ';' + accountMapForCallout.get(accountId).get('vatNumber');

                // String cc = accountMapForCallout.get(accountId).get('countryCode');
                // String vatnr = accountMapForCallout.get(accountId).get('vatNumber');

                if (triggerFutureClass == null) {
                    paramList.add(param);
                    // VAT_ViesCallout.MakeCallout(accountId, cc, vatnr);
                }
            }
            // Call @future method to get VIES Check of VAT number
            VAT_ViesCallout.MakeCallout(paramList);
        }

        System.debug('VAT_checkVat - CheckVatOnInsert - end');
    }

}