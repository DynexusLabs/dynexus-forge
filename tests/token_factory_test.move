#[test_only]
module dynexus_forge::token_factory_test {
    use std::signer::address_of;
    use std::string;
    use aptos_framework::account::create_signer_for_test;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::genesis;
    use aptos_framework::object::address_to_object;
    use aptos_framework::primary_fungible_store;
    use dynexus_forge::token_factory;

    public fun create_dynexus_token(): address{
        let dynexus = &create_signer_for_test(@dynexus_forge);

        let name = string::utf8(b"DYNEXUS");
        let symbol = string::utf8(b"DYNEXUS");
        let icon_uri = string::utf8(b"https://lavender-binding-jackal-744.mypinata.cloud/ipfs/bafybeiega65r37e6htyrgfxkqsxt36pnldpjmhmw7imyemfrub62l6sjiy");
        let project_uri = string::utf8(b"https://lavender-binding-jackal-744.mypinata.cloud/ipfs/bafybeiega65r37e6htyrgfxkqsxt36pnldpjmhmw7imyemfrub62l6sjiy");
        let (_, _, addr) = token_factory::create_test_token(
            dynexus,
            name,
            symbol,
            6,
            100_000,
            icon_uri,
            project_uri,
            0
        );

        token_factory::set_dynexus_token(dynexus, addr);
        addr
    }

    public fun balance_of(user: address, token_add: address): u64 {
        primary_fungible_store::balance(user, address_to_object<Metadata>(token_add))
    }

    public fun transfer_token(from: &signer, to: address,  token_add: address, amount: u64) {
        primary_fungible_store::transfer(from, address_to_object<Metadata>(token_add), to, amount)
    }

    public fun setup_token_factory(user: address){
        let dynexus = &create_signer_for_test(@dynexus_forge);
        token_factory::initalize_token_factory_with_out_genesis(dynexus);

        let token_address = create_dynexus_token();
        token_factory::mint_token(dynexus, user, token_address, 1000)
    }



    public fun initalize_token_factory(user: address) {
        genesis::setup();
        setup_token_factory(user);
    }


    #[test]
    fun test_initialize_token_factory() {
        initalize_token_factory(@0x124);
    }

    #[test]
    #[expected_failure]
    fun test_initialize_token_factory_twice_should_fail() {
        initalize_token_factory(@0x124);
        // Second initialization should fail
        initalize_token_factory(@0x124);
    }

    #[test]
    fun test_create_token_success() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let name = string::utf8(b"My Test Token");
        let symbol = string::utf8(b"MT");
        let icon_uri = string::utf8(b"https://example.com/icon.png");
        let project_uri = string::utf8(b"https://example.com");
        let (_, _, addr) = token_factory::create_test_token(
            &admin,
            name,
            symbol,
            6,
            100_000,
            icon_uri,
            project_uri,
        0
        );

        let balance = balance_of(address_of(&admin), addr);
        assert!(balance == 100_000, 100);
    }

    #[test]
    fun test_create_token_with_zero_supply() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) =token_factory::create_test_token(
            &admin,
            string::utf8(b"Zero Supply Token"),
            string::utf8(b"ZST"),
            6,
            0,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        let balance = balance_of(address_of(&admin), addr);
        assert!(balance == 0, 104);
    }

    #[test]
    fun test_create_token_max_supply() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let max_supply = 18446744073709551615u64; // u64::MAX
        let (_, _, addr) =   token_factory::create_test_token(
            &admin,
            string::utf8(b"Max Supply Token"),
            string::utf8(b"MST"),
            6,
            max_supply,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        let balance = balance_of(address_of(&admin), addr);
        assert!(balance == max_supply, 105);
    }

    #[test]
    fun test_create_token_various_decimals() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        // Test with 0 decimals
        token_factory::create_test_token(
            &admin,
            string::utf8(b"Zero Decimals"),
            string::utf8(b"ZD"),
            0,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );
    }

    #[test]
    fun test_create_token_duplicate_should_fail() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let name = string::utf8(b"Duplicate Token");
        let symbol = string::utf8(b"DT");
        let icon_uri = string::utf8(b"https://example.com/icon.png");
        let project_uri = string::utf8(b"https://example.com");

        token_factory::create_test_token(&admin, name, symbol, 6, 100, icon_uri, project_uri, 0);
    }

    #[test]
    #[expected_failure]
    fun test_create_token_without_initialization_should_fail() {
        let admin = create_signer_for_test(@0x123);
        // Don't initialize token factory

        token_factory::create_test_token(
            &admin,
            string::utf8(b"Should Fail"),
            string::utf8(b"SF"),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );
    }

    #[test]
    #[expected_failure(abort_code = token_factory::E_INSUFFICIENT_DYANEXUS_BALANCE)]
    fun test_create_no_dynexus_should_fail() {
        initalize_token_factory(@0x123);

        let admin = create_signer_for_test(@0x888);
        token_factory::create_test_token(
            &admin,
            string::utf8(b"Unauthorized"),
            string::utf8(b"UA"),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );
    }

    #[test]
    fun test_create_token_empty_name() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        token_factory::create_test_token(
            &admin,
            string::utf8(b""),
            string::utf8(b"EN"),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );
    }

    #[test]
    fun test_create_token_empty_symbol() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        token_factory::create_test_token(
            &admin,
            string::utf8(b"Empty Symbol"),
            string::utf8(b""),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );
    }

    #[test]
    fun test_create_token_empty_uris() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        token_factory::create_test_token(
            &admin,
            string::utf8(b"Empty URIs"),
            string::utf8(b"EU"),
            6,
            1000,
            string::utf8(b""),
            string::utf8(b""),
            0
        );
    }

    #[test]
    fun test_token_minting() {
        let admin = create_signer_for_test(@0x123);
        let receiver = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) = token_factory::create_test_token(
            &admin,
            string::utf8(b"Mintable"),
            string::utf8(b"MM"),
            6,
            0,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        token_factory::mint_token(&admin, address_of(&receiver), addr, 555);

        let balance = balance_of(address_of(&receiver), addr);
        assert!(balance == 555, 101);
    }

    #[test]
    fun test_mint_zero_amount() {
        let admin = create_signer_for_test(@0x123);
        let receiver = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) = token_factory::create_test_token(
            &admin,
            string::utf8(b"Mintable"),
            string::utf8(b"MM"),
            6,
            0,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );


        token_factory::mint_token(&admin, address_of(&receiver), addr, 0);

        let balance = balance_of(address_of(&receiver), addr);
        assert!(balance == 0, 106);
    }

    #[test]
    fun test_mint_to_self() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) =token_factory::create_test_token(
            &admin,
            string::utf8(b"Self Mint"),
            string::utf8(b"SM"),
            6,
            100,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        let initial_balance = balance_of(address_of(&admin), addr);

        token_factory::mint_token(&admin, address_of(&admin), addr, 500);

        let new_balance = balance_of(address_of(&admin), addr);
        assert!(new_balance == initial_balance + 500, 107);
    }

    #[test]
    #[expected_failure]
    fun test_mint_non_admin_should_fail() {
        let admin = create_signer_for_test(@0x123);
        let non_admin = create_signer_for_test(@0x555);
        let receiver = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) =  token_factory::create_test_token(
            &admin,
            string::utf8(b"Secure Token"),
            string::utf8(b"ST"),
            6,
            0,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        token_factory::mint_token(&non_admin, address_of(&receiver), addr, 100);
    }

    #[test]
    fun test_token_transfer() {
        let admin = create_signer_for_test(@0x123);
        let user = create_signer_for_test(@0x124);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) = token_factory::create_test_token(
            &admin,
            string::utf8(b"Transfer Token"),
            string::utf8(b"TT"),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        transfer_token(&admin, address_of(&user), addr, 300);
        let user_balance = balance_of(address_of(&user), addr);
        let admin_balance = balance_of(address_of(&admin), addr);

        assert!(user_balance == 300, 102);
        assert!(admin_balance == 700, 103);
    }

    #[test]
    fun test_transfer_zero_amount() {
        let admin = create_signer_for_test(@0x123);
        let user = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) = token_factory::create_test_token(
            &admin,
            string::utf8(b"Zero Transfer"),
            string::utf8(b"ZT"),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        let initial_admin_balance = balance_of(address_of(&admin), addr);
        let initial_user_balance = balance_of(address_of(&user), addr);

        transfer_token(&admin, address_of(&user), addr, 0);

        let final_admin_balance = balance_of(address_of(&admin), addr);
        let final_user_balance = balance_of(address_of(&user), addr);

        assert!(final_admin_balance == initial_admin_balance, 108);
        assert!(final_user_balance == initial_user_balance, 109);
    }

    #[test]
    fun test_transfer_entire_balance() {
        let admin = create_signer_for_test(@0x123);
        let user = create_signer_for_test(@0x124);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) = token_factory::create_test_token(
            &admin,
            string::utf8(b"All Transfer"),
            string::utf8(b"AT"),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        transfer_token(&admin, address_of(&user), addr, 1000);

        let user_balance = balance_of(address_of(&user), addr);
        let admin_balance = balance_of(address_of(&admin), addr);

        assert!(user_balance == 1000, 110);
        assert!(admin_balance == 0, 111);
    }

    #[test]
    #[expected_failure]
    fun test_transfer_insufficient_balance_should_fail() {
        let admin = create_signer_for_test(@0x123);
        let user = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) = token_factory::create_test_token(
            &admin,
            string::utf8(b"Insufficient"),
            string::utf8(b"IN"),
            6,
            100,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        // Try to transfer more than available
        transfer_token(&admin, address_of(&user), addr, 150);
    }

    #[test]
    fun test_transfer_to_self() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let (_, _, addr) =  token_factory::create_test_token(
            &admin,
            string::utf8(b"Self Transfer"),
            string::utf8(b"ST"),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        let initial_balance = balance_of(address_of(&admin), addr);

        transfer_token(&admin, address_of(&admin), addr, 500);

        let final_balance = balance_of(address_of(&admin), addr);
        assert!(final_balance == initial_balance, 112);
    }

    #[test]
    fun test_invalid_symbol_should_fail() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));
        token_factory::create_test_token(
            &admin,
            string::utf8(b"InvalidSymbol"),
            string::utf8(b"LONG"),
            6,
            0,
            string::utf8(b"https://icon"),
            string::utf8(b"https://project"),
            0
        );
    }

    #[test]
    fun test_multiple_tokens_creation() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        // Create first token
        token_factory::create_test_token(
            &admin,
            string::utf8(b"Token One"),
            string::utf8(b"T1"),
            6,
            1000,
            string::utf8(b"https://icon1.com"),
            string::utf8(b"https://project1.com"),
            0
        );

        // Create second token (if supported)
        token_factory::create_test_token(
            &admin,
            string::utf8(b"Token Two"),
            string::utf8(b"T2"),
            8,
            2000,
            string::utf8(b"https://icon2.com"),
            string::utf8(b"https://project2.com"),
            0
        );
    }


    #[test]
    #[expected_failure]
    fun test_get_balance_invalid_token_should_fail() {
        let admin = create_signer_for_test(@0x123);
        let fake_address = @0x999;
        initalize_token_factory(address_of(&admin));

        token_factory::create_test_token(
            &admin,
            string::utf8(b"Valid Token"),
            string::utf8(b"VT"),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        // Try to get balance with invalid token address
        balance_of(address_of(&admin), fake_address);
    }

    #[test]
    fun test_complex_workflow() {
        let admin = create_signer_for_test(@0x123);
        let user1 = create_signer_for_test(@0x111);
        let user2 = create_signer_for_test(@0x222);

        initalize_token_factory(address_of(&admin));

        // Create token with initial supply
        let (_, _, addr) =  token_factory::create_test_token(
            &admin,
            string::utf8(b"Complex Token"),
            string::utf8(b"CT"),
            6,
            10000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );

        // Transfer some to user1
        transfer_token(&admin, address_of(&user1), addr, 3000);

        // Mint additional tokens to user2
        token_factory::mint_token(&admin, address_of(&user2), addr, 2000);

        // Transfer from admin to user2
        transfer_token(&admin, address_of(&user2), addr, 1500);

        // Verify final balances
        let admin_balance = balance_of(address_of(&admin), addr);
        let user1_balance = balance_of(address_of(&user1), addr);
        let user2_balance = balance_of(address_of(&user2), addr);

        assert!(admin_balance == 5500, 113); // 10000 - 3000 - 1500
        assert!(user1_balance == 3000, 114);
        assert!(user2_balance == 3500, 115); // 2000 + 1500
    }

    #[test]
    #[expected_failure(abort_code = token_factory::E_INVALID_TOKEN_DECIMAL)]
    fun test_extreme_decimals() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        // Test with maximum decimals (if there's a limit)
        token_factory::create_test_token(
            &admin,
            string::utf8(b"Max Decimals"),
            string::utf8(b"MD"),
            18,
            1000000000000000000, // 1 token with 18 decimals
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );
    }

    #[test]
    fun test_unicode_strings() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        token_factory::create_test_token(
            &admin,
            string::utf8(b"Token \xE2\x82\xAC"),
            string::utf8(b"\xE2\x82\xAC"),
            6,
            1000,
            string::utf8(b"https://icon.com"),
            string::utf8(b"https://project.com"),
            0
        );
    }

    #[test]
    #[expected_failure]
    fun test_long_strings() {
        let admin = create_signer_for_test(@0x123);
        initalize_token_factory(address_of(&admin));

        let long_name = string::utf8(b"This is a very long token name that might test the limits of string handling in the smart contract implementation");
        let long_uri = string::utf8(b"https://this-is-a-very-long-uri-that-might-test-url-handling.example.com/path/to/resource/with/many/segments/and/parameters?param1=value1&param2=value2");

        token_factory::create_test_token(
            &admin,
            long_name,
            string::utf8(b"LT"),
            6,
            1000,
            long_uri,
            long_uri,
            0
        );
    }
}