module dynexus_forge::token_factory {

    use std::option;
    use std::signer::address_of;
    use std::string::{String};
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata};
    use aptos_framework::object::{Self, ExtendRef, address_to_object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;


    //
    // Constants
    //
    /// Contract addresss
    const CA: address = @dynexus_forge;
    /// Token creation seed
    const TOKEN_SEED: vector<u8> = b"DYNEXUS";
    /// Token factory object creation seed
    const TOKEN_FACTORY_OBJECT_SEED: vector<u8> = b"DYNEXUS_FORGE_OWNER";
    /// Max token decimal
    const MAX_DECIMAL: u8 = 8;
    /// Max token uri length
    const MAX_URI_LENGTH: u32 = 512;

    //
    // Errors
    //
    /// Token already exists in the registry.
    const E_TOKEN_ALREADY_EXISTS: u64 = 1;

    /// User has insufficient balance for the operation.
    const E_INSUFFICIENT_BALANCE: u64 = 3;

    /// Requested swap pair or route was not found.
    const E_SWAP_NOT_FOUND: u64 = 4;

    /// Swap request has expired and is no longer valid.
    const E_SWAP_EXPIRED: u64 = 5;

    /// User is not the owner and is not authorized to perform this action.
    const E_NOT_AN_OWNER: u64 = 6;

    /// Token not exists in the registry.
    const E_TOKEN_NOT_EXISTS: u64 = 7;

    /// Token factory not initialized yet..
    const E_REGISTRY_NOT_EXISTS: u64 = 8;

    /// Token deciaml should less then 8
    const E_INVALID_TOKEN_DECIMAL: u64 = 9;

    /// Token uri length should less then 512
    const E_INVALID_URI_LENGTH: u64 = 10;

    /// Token address are same
    const E_INVALID_TOKEN_ADDRESS: u64 = 11;

    /// Invalid Dynexus fees
    const E_INVALID_FEE: u64 = 12;

    /// User has insufficient balance of dynexus.
    const E_INSUFFICIENT_DYANEXUS_BALANCE: u64 = 12;


    //
    // Structs
    //
    struct TokenRegistry has key {
        //
        dynexus_token: address,

        // Admin controls
        admin: address,
        plateform_fee_rate: u64,

        // Statistics
        total_users: u64,

        // extending object signer
        extend_ref: ExtendRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ManageFungibleAsset has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        creator: address
    }

    struct TokenList has copy, drop {
        name: String,
        symbol: String,
        token_address: address
    }

    //
    // Events
    //

    #[event]
    struct TokenCreated has drop, store {
        creator: address,
        token_address: address,
        timestamp: u64
    }

    #[event]
    struct TokenTransfer has drop, store {
        from: address,
        to: address,
        token_address: address,
        amount: u64,
    }

    //
    // Inttialize Function
    //
    /// Initializes the Token Factory module
    ///
    /// # Parameters
    /// - `admin`: signer of the admin deploying the token factory
    fun init_module(admin: &signer) {
        let admin_addr = address_of(admin);
        let constructor_ref =
            &object::create_named_object(admin, TOKEN_FACTORY_OBJECT_SEED);
        let obj_signer = &object::generate_signer(constructor_ref);
        let extend_ref = object::generate_extend_ref(constructor_ref);

        move_to(
            obj_signer,
            TokenRegistry {
                admin: admin_addr,
                total_users: 0,
                plateform_fee_rate: 5, // DYNEXUS token
                extend_ref,
                dynexus_token: @0x0
            }
        );
    }

    //
    // Token Creation & Management
    //

    public entry fun set_dynexus_token(owner: &signer, new_address: address) acquires TokenRegistry {
        let owner_addr = address_of(owner);
        let owner_obj_addr = object::create_object_address(&owner_addr, TOKEN_FACTORY_OBJECT_SEED);
        let registry = borrow_global_mut<TokenRegistry>(owner_obj_addr);

        assert!(registry.admin == owner_addr , E_NOT_AN_OWNER);
        assert!(registry.dynexus_token != new_address , E_INVALID_TOKEN_ADDRESS);
        registry.dynexus_token = new_address;
    }

    public entry fun set_dynexus_plateform_fee_rate(owner: &signer, new_fee: u64) acquires TokenRegistry {
        let owner_addr = address_of(owner);
        let owner_obj_addr = object::create_object_address(&owner_addr, TOKEN_FACTORY_OBJECT_SEED);
        let registry = borrow_global_mut<TokenRegistry>(owner_obj_addr);

        assert!(registry.admin == owner_addr , E_NOT_AN_OWNER);
        assert!(registry.plateform_fee_rate != new_fee , E_INVALID_TOKEN_ADDRESS);
        registry.plateform_fee_rate = new_fee;
    }

    /// Creates a custom fungible token in the DYNA ecosystem.
    ///
    /// # Parameters
    /// - `creator`: signer of the token creator
    /// - `name`: Full name of the token
    /// - `symbol`: Short symbol (max 2 chars)
    /// - `decimals`: Decimal precision (max 18)
    /// - `inital_supply`: Initial amount of tokens to mint to creator
    /// - `icon_uri`: Link to token icon
    /// - `project_uri`: Project website or metadata link
    ///
    /// # Returns
    /// - `(creator_address, token_address)`
    ///
    /// # Aborts With
    /// - `E_SYMBOL_TOO_LONG` if symbol > MAX_SYMBOL_LENGTH
    /// - `E_TOKEN_ALREADY_EXISTS` if token with same name/symbol exists
    /// - `E_INVALID_PARAMETERS` for invalid decimals or URIs
    public entry fun create_token(
        creator: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        inital_supply: u64,
        icon_uri: String,
        project_uri: String
    ) acquires TokenRegistry, ManageFungibleAsset {

        let creator_addr = address_of(creator);
        let registry_addr = get_token_factory_object_addr();
        let registry = borrow_global_mut<TokenRegistry>(registry_addr);

        // Apply Charges
        if(creator_addr != @dynexus_forge){
            let dynexus_metadata = address_to_object<Metadata>(registry.dynexus_token);
            let balance = primary_fungible_store::balance(creator_addr, dynexus_metadata);
            assert!(balance >= registry.plateform_fee_rate,  E_INSUFFICIENT_DYANEXUS_BALANCE);
            primary_fungible_store::transfer(creator, dynexus_metadata, registry.admin, registry.plateform_fee_rate);
        };


        let token_seed = create_token_seed(&name, &symbol);
        let token_address = object::create_object_address(&creator_addr, token_seed);

        assert!(!exists<ManageFungibleAsset>(token_address), E_TOKEN_ALREADY_EXISTS);
        assert!(decimals <= MAX_DECIMAL, E_INVALID_TOKEN_DECIMAL);
        assert!(icon_uri.length() <= (MAX_URI_LENGTH as u64) || project_uri.length() <= (MAX_URI_LENGTH as u64), E_INVALID_URI_LENGTH);

        let constuctor_ref = object::create_named_object(creator, token_seed);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constuctor_ref,
            option::none(),
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri
        );

        let mint_ref = fungible_asset::generate_mint_ref(&constuctor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constuctor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(&constuctor_ref);
        let token_signer = object::generate_signer(&constuctor_ref);
        let token_address = address_of(&token_signer);

        move_to(
            &token_signer,
            ManageFungibleAsset { mint_ref, burn_ref, transfer_ref, creator: creator_addr }
        );

        registry.total_users += 1;

        if (inital_supply > 0) {
            let manage_ref = borrow_global<ManageFungibleAsset>(token_address);
            let fa = fungible_asset::mint(&manage_ref.mint_ref, inital_supply);
            primary_fungible_store::deposit(creator_addr, fa);
        };

        event::emit(
            TokenCreated {
                creator: creator_addr,
                token_address,
                timestamp: timestamp::now_seconds()
            }
        );

    }

    /// Mints additional supply of a DYNA-based token to a user
    ///
    /// # Parameters
    /// - `owner`: signer of token owner/creator
    /// - `to`: address to receive minted tokens
    /// - `token_address`: address of the token to mint
    /// - `amount`: quantity to mint
    ///
    /// # Aborts With
    /// - `E_NOT_AN_OWNER` if caller is not token creator
    public entry fun mint_token(
        owner: &signer,
        to: address,
        token_address: address,
        amount: u64
    ) acquires ManageFungibleAsset {
        let owner_addr = address_of(owner);

        // Check `ManageFungibleAsset` exist
        assert!(exists<ManageFungibleAsset>(token_address), E_NOT_AN_OWNER);

        // Check ownership
        let manage_auth = borrow_global<ManageFungibleAsset>(token_address);
        assert!(manage_auth.creator == owner_addr, E_NOT_AN_OWNER);

        // Transfer minted FA
        let token = fungible_asset::mint(&manage_auth.mint_ref, amount);
        primary_fungible_store::deposit_with_ref(&manage_auth.transfer_ref, to, token);
    }

    //
    // Helper Functions
    //

    /// Create token seed
    fun create_token_seed(name: &String, symbol: &String): vector<u8> {
        let seed = TOKEN_SEED;
        seed.append(*name.bytes());
        seed.append(*symbol.bytes());
        seed
    }

    //
    // View functions
    //
    #[view]
    public fun get_token_factory_object_addr(): address {
        object::create_object_address(&CA, TOKEN_FACTORY_OBJECT_SEED)
    }

    #[view]
    public fun get_token_fa_address(creator: address, name:String, symbol: String): address {
        let seed = create_token_seed(&name, &symbol);
        object::create_object_address(&creator, seed)
    }

    //
    // Test functions
    //
    #[test_only]
    public fun initalize_token_factory_with_out_genesis(admin: &signer){
        init_module(admin)
    }

    #[test_only]
    public fun create_test_token(
        creator: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        inital_supply: u64,
        icon_uri: String,
        project_uri: String,
        _index: u64
    ): (String, String, address) acquires TokenRegistry, ManageFungibleAsset {
        create_token(
            creator,
            name,
            symbol,
            decimals,
            inital_supply,
            icon_uri,
            project_uri
        );

        let seed = create_token_seed(&name, &symbol);
        (name, symbol, object::create_object_address(&address_of(creator), seed))
    }
}