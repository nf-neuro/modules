include { RECONST_DIFFUSIVITYPRIORS } from '../../../modules/nf-neuro/reconst/diffusivitypriors/main'
include { RECONST_MEANDIFFUSIVITYPRIORS } from '../../../modules/nf-neuro/reconst/meandiffusivitypriors/main'
include { RECONST_NODDI          } from '../../../modules/nf-neuro/reconst/noddi/main'
include { RECONST_FREEWATER      } from '../../../modules/nf-neuro/reconst/freewater/main'
include { RECONST_DTIMETRICS as FW_CORRECTED_DTIMETRICS } from '../../../modules/nf-neuro/reconst/dtimetrics/main'
workflow RECONST_FW_NODDI {

    take:
    dwi_bval_bvec
    brain_mask
    fa_ad_rd_md
    diffusivities // multiMap channel with para_diff, iso_diff, perp_diff_min, perp_diff_max

    main:

    ch_versions = channel.empty()

    // Make sure that at least one of the two reconstructions is requested
    if (!params.run_noddi && !params.run_freewater) {
        error "At least one of params.run_noddi or params.run_freewater must be true to run this subworkflow."
    }

    // Prepase base input channels
    ch_base_noddi = dwi_bval_bvec.join(brain_mask)
    ch_base_freewater = dwi_bval_bvec.join(brain_mask)

    // Format inputs to get the same shape of tuple for all possible cases.
    def format_input = { ch ->
        ch.ifEmpty { [[tag: 'empty'], null] }
            .map { it ->
                // If we have subject-bound, leave as is
                if (it instanceof List && it.size() == 2)
                    return it
                // If we have a single value, convert to tuple
                else {
                    return [[tag: 'global'], it]
                }
            }
    }
    para_diff = format_input(diffusivities.para_diff)
    iso_diff = format_input(diffusivities.iso_diff)
    perp_diff_min = format_input(diffusivities.perp_diff_min)
    perp_diff_max = format_input(diffusivities.perp_diff_max)

    // Combine all diffusivity priors together, and assess wheter they are
    // empty, single value, or per-subject values.
    ch_priors_branched = para_diff
        .combine( iso_diff )
        .combine( perp_diff_min )
        .combine( perp_diff_max )
        .map { items ->
            // Flatten the combined tuples
            def flattened = items.flatten()

            def para_t = flattened[0..1]
            def iso_t = flattened[2..3]
            def perp_min_t = flattened[4..5]
            def perp_max_t = flattened[6..7]

            // Assertions to check which one we got
            def has_para = !(para_t[0].containsKey('tag') && para_t[0].tag == 'empty')
            def has_iso = !(iso_t[0].containsKey('tag') && iso_t[0].tag == 'empty')
            def has_perp_min = !(perp_min_t[0].containsKey('tag') && perp_min_t[0].tag == 'empty')
            def has_perp_max = !(perp_max_t[0].containsKey('tag') && perp_max_t[0].tag == 'empty')

            // Validation checks for NODDI
            if (params.run_noddi && (has_para != has_iso)) {
                error "For NODDI reconstruction, both para_diff and iso_diff must be provided together."
            }

            // Validation checks for Freewater
            if (params.run_freewater && (has_para != has_iso || has_para != has_perp_min || has_para != has_perp_max)) {
                error "For Freewater Elimination reconstruction, para_diff, iso_diff, perp_diff_min and perp_diff_max "
                    "must be provided together."
            }

            // Check if per-subject values were provided
            def subject_bound = has_para && para_t[0].containsKey('id') && !para_t[0].containsKey('tag')

            // Warn if both custom priors and averaging are requested
            if ((has_para || has_iso) && params.average_diff_priors) {
                log.warn "Both custom diffusivity priors and params.average_diff_priors parameter were provided. " +
                    "The specified custom diffusivity priors will be used across subjects."
            }

            return tuple(has_para, has_iso, has_perp_min, has_perp_max, subject_bound,
                para_t, iso_t, perp_min_t, perp_max_t)
        }
        .branch{
            has_para, has_iso, has_perp_min, has_perp_max, subject_bound,
            para_t, iso_t, perp_min_t, perp_max_t ->

            custom_subject_bound: (has_para && has_iso) && subject_bound
                return tuple(para_t, iso_t, perp_min_t, perp_max_t)
            custom: (has_para && has_iso) && !subject_bound
                return tuple(para_t[1], iso_t[1], has_perp_min ? perp_min_t[1] : null, has_perp_max ? perp_max_t[1] : null)
            compute: true
                // No custom priors provided, will compute them later
                return true
        }

    // Prepare NODDI inputs. This channel will be combined/joined in the
    // lines that follow with diffusivity priors w.r.t the following 3 scenarios:
    // Option 1: The user specifies the diffusivity priors to use (via params.para_diff and params.iso_diff).
    // Option 2: The user wants to compute the mean diffusivity priors across subjects. (Recommended)
    // Option 3: The user wants to compute diffusivity priors for each subject individually.

    // Branch 1: Custom diffusivity priors provided per-subject
    ch_custom_subject = ch_priors_branched.custom_subject_bound
        .multiMap{ para_t, iso_t, perp_min_t, perp_max_t ->
            para: para_t
            iso: iso_t
            perp_min: perp_min_t
            perp_max: perp_max_t
        }

    ch_noddi_custom_subj = ch_base_noddi
        .join( ch_custom_subject.para )         // para
        .join( ch_custom_subject.iso )          // iso

    ch_freewater_custom_subj = ch_base_freewater
        .join( ch_custom_subject.para )         // para
        .join( ch_custom_subject.iso )          // iso
        .join( ch_custom_subject.perp_min )     // perp_min
        .join( ch_custom_subject.perp_max )     // perp_max

    // Branch 2: Custom diffusivity priors provided (single value across subjects)
    ch_custom = ch_priors_branched.custom
        .multiMap{ para, iso, perp_min, perp_max ->
            para: para
            iso: iso
            perp_min: perp_min
            perp_max: perp_max
        }

    ch_noddi_custom = ch_base_noddi
        .combine( ch_custom.para )        // para
        .combine( ch_custom.iso )         // iso

    ch_freewater_custom = ch_base_freewater
        .combine( ch_custom.para )        // para
        .combine( ch_custom.iso )         // iso
        .combine( ch_custom.perp_min )    // perp_min
        .combine( ch_custom.perp_max )    // perp_max

    // Branch 3: Compute diffusivity priors
    ch_compute_diff_priors = ch_priors_branched.compute
        .combine( fa_ad_rd_md )
        .map{ bool, meta, fa, ad, rd, md ->
            return tuple(meta, fa, ad, rd, md)
        }

    RECONST_DIFFUSIVITYPRIORS( ch_compute_diff_priors )
    ch_versions = ch_versions.mix(RECONST_DIFFUSIVITYPRIORS.out.versions)

    // Then compute mean diffusivity priors across subjects.
    if (params.average_diff_priors) {
        RECONST_MEANDIFFUSIVITYPRIORS(
            RECONST_DIFFUSIVITYPRIORS.out.para_diff_file
                .map{ _meta, path -> path }
                .collect(),
            RECONST_DIFFUSIVITYPRIORS.out.iso_diff_file
                .map{ _meta, path -> path }
                .collect(),
            RECONST_DIFFUSIVITYPRIORS.out.perp_diff_file
                .map{ _meta, path -> path }
                .collect()
        )
        ch_versions = ch_versions.mix(RECONST_MEANDIFFUSIVITYPRIORS.out.versions)

        ch_noddi_computed = ch_base_noddi
            .combine(RECONST_MEANDIFFUSIVITYPRIORS.out.mean_para_diff)
            .combine(RECONST_MEANDIFFUSIVITYPRIORS.out.mean_iso_diff)
        ch_freewater_computed = ch_base_freewater
            .combine(RECONST_MEANDIFFUSIVITYPRIORS.out.mean_para_diff)
            .combine(RECONST_MEANDIFFUSIVITYPRIORS.out.mean_iso_diff)
            .combine(RECONST_MEANDIFFUSIVITYPRIORS.out.min_perp_diff)
            .combine(RECONST_MEANDIFFUSIVITYPRIORS.out.max_perp_diff)
    }
    else {
        ch_noddi_computed = ch_base_noddi
            .join(RECONST_DIFFUSIVITYPRIORS.out.mean_para_diff)
            .join(RECONST_DIFFUSIVITYPRIORS.out.mean_iso_diff)
        ch_freewater_computed = ch_base_freewater
            .join(RECONST_DIFFUSIVITYPRIORS.out.mean_para_diff)
            .join(RECONST_DIFFUSIVITYPRIORS.out.mean_iso_diff)
            .join(RECONST_DIFFUSIVITYPRIORS.out.min_perp_diff)
            .join(RECONST_DIFFUSIVITYPRIORS.out.max_perp_diff)
    }

    if (params.run_noddi) {
        ch_noddi_input = ch_noddi_custom_subj
            .mix( ch_noddi_custom )
            .mix( ch_noddi_computed )
            .map{ meta, dwi, bval, bvec, b0_mask, para, iso ->
                [meta, dwi, bval, bvec, b0_mask, [], para, iso] }

        RECONST_NODDI( ch_noddi_input )
        ch_versions = ch_versions.mix(RECONST_NODDI.out.versions)
    }

    if (params.run_freewater) {
        ch_freewater_input = ch_freewater_custom_subj
            .mix( ch_freewater_custom )
            .mix( ch_freewater_computed )
            .map{ meta, dwi, bval, bvec, b0_mask, para, iso, perp_min, perp_max ->
                [meta, dwi, bval, bvec, b0_mask, [], para, iso, perp_min, perp_max] }

        RECONST_FREEWATER( ch_freewater_input )
        ch_versions = ch_versions.mix(RECONST_FREEWATER.out.versions)

        // -- Need to reprocess RECONST_DTIMETRICS to get
        //  FW corrected FA, MD, RD, AD, etc.
        //  using the FW corrected DWI.
        ch_fw_corrected_dti_metrics = RECONST_FREEWATER.out.dwi_fw_corrected
            .join(dwi_bval_bvec)
            .join(brain_mask)
            .map {
                // Remove the original dwi from the join
                meta, dwi_fw_corrected, _dwi_orig, bval, bvec, b0_mask ->
                    [meta, dwi_fw_corrected, bval, bvec, b0_mask]
            }

        FW_CORRECTED_DTIMETRICS( ch_fw_corrected_dti_metrics )
        ch_versions = ch_versions.mix(FW_CORRECTED_DTIMETRICS.out.versions)
    }

    emit:
    // NODDI
    noddi_dir           = params.run_noddi ? RECONST_NODDI.out.dir : channel.empty()
    noddi_isovf         = params.run_noddi ? RECONST_NODDI.out.isovf : channel.empty()
    noddi_icvf          = params.run_noddi ? RECONST_NODDI.out.icvf : channel.empty()
    noddi_ecvf          = params.run_noddi ? RECONST_NODDI.out.ecvf : channel.empty()
    noddi_odi           = params.run_noddi ? RECONST_NODDI.out.odi : channel.empty()

    // Freewater Elimination
    fw_dwi              = params.run_freewater ? RECONST_FREEWATER.out.dwi_fw_corrected : channel.empty()
    fw_dir              = params.run_freewater ? RECONST_FREEWATER.out.dir : channel.empty()
    fw_fibervolume      = params.run_freewater ? RECONST_FREEWATER.out.fibervolume : channel.empty()
    fw_fwf              = params.run_freewater ? RECONST_FREEWATER.out.fwf : channel.empty()
    fw_nrmse            = params.run_freewater ? RECONST_FREEWATER.out.nrmse : channel.empty()

    fw_dti_tensor       = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.tensor : channel.empty()
    fw_dti_md           = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.md : channel.empty()
    fw_dti_rd           = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.rd : channel.empty()
    fw_dti_ad           = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.ad : channel.empty()
    fw_dti_fa           = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.fa : channel.empty()
    fw_dti_rgb          = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.rgb : channel.empty()
    fw_dti_peaks        = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.evecs_v1 : channel.empty()
    fw_dti_evecs        = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.evecs : channel.empty()
    fw_dti_evals        = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.evals : channel.empty()
    fw_dti_residual     = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.residual : channel.empty()
    fw_dti_ga           = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.ga : channel.empty()
    fw_dti_mode         = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.mode : channel.empty()
    fw_dti_norm         = params.run_freewater ? FW_CORRECTED_DTIMETRICS.out.norm : channel.empty()

    versions = ch_versions
}
